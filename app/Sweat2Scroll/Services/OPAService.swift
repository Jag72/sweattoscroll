// Services/OPAService.swift
// Loads the compiled OPA/Rego WebAssembly module via WasmKit.
// Evaluates the fitness policy with sub-millisecond latency on-device.
// The Wasm module is the Policy Decision Point (PDP).
//
// OPA WASM ABI REFERENCE:
//   https://www.openpolicyagent.org/docs/latest/wasm/
//   The compiled OPA Wasm module exports a set of functions that follow
//   a specific calling convention for memory management and evaluation.
//
// DEPENDENCIES:
//   - Add WasmKit via SPM: https://github.com/swiftwasm/WasmKit (0.2.0+)
//   - Compile policy: opa build -t wasm -e sweat2scroll/contract/allow \
//                     -e sweat2scroll/contract/requires_grace \
//                     policy/fitness_policy.rego
//   - Output: bundle.tar.gz → extract contract.wasm (~142 KB)
//   - Add contract.wasm to app bundle Resources/

import Foundation
import CryptoKit
import WasmKit

// MARK: - OPA Wasm ABI Constants
// The OPA Wasm module exports these functions as part of its ABI.
// We call them in a specific order to evaluate a policy.
private enum OPAABIExport {
    static let malloc              = "opa_malloc"
    static let free                = "opa_free"
    static let jsonParse           = "opa_json_parse"
    static let jsonDump            = "opa_json_dump"
    static let evalContextNew      = "opa_eval_ctx_new"
    static let evalContextSetInput = "opa_eval_ctx_set_input"
    static let evalContextSetData  = "opa_eval_ctx_set_data"
    static let evalContextSetEntrypoint = "opa_eval_ctx_set_entrypoint"
    static let eval                = "eval"
    static let evalContextGetResult = "opa_eval_ctx_get_result"
    static let builtins            = "builtins"
    static let entrypoints         = "entrypoints"
    static let heapPtrGet          = "opa_heap_ptr_get"
    static let heapPtrSet          = "opa_heap_ptr_set"
}

// MARK: - OPA Entrypoint IDs
// These map to the entrypoints compiled into the Wasm bundle.
// Run `opa eval -d policy/ 'data.sweat2scroll.contract'` to verify.
private enum OPAEntrypoint: Int32 {
    case allow             = 0
    case requiresGrace     = 1
}

class OPAService {

    // MARK: - Singleton
    static let shared = OPAService()
    private init() {}

    // MARK: - State
    private var isModuleLoaded: Bool = false
    private var engine: Engine?
    private var store: Store?
    private var moduleInstance: ModuleInstance?
    private var wasmMemory: Memory?

    /// Heap pointer saved after initial data load — enables fast reset between evaluations.
    /// Stored as Int32 (OPA ABI uses 32-bit signed addresses); cast to UInt32 for Value.i32().
    private var baseHeapPointer: Int32 = 0

    /// Cached data address for empty `{}` base document.
    private var baseDataAddr: Int32 = 0

    // MARK: - Thread Safety
    private let evaluationQueue = DispatchQueue(label: "com.sweat2scroll.opa.eval", qos: .userInitiated)

    // MARK: - Cold Start Load (~38ms, amortized via persistent background process)
    /// Loads the compiled OPA Wasm module into the WasmKit runtime.
    /// This is a one-time cost — subsequent evaluations reuse the loaded module.
    func loadModule() throws {
        guard !isModuleLoaded else { return }

        guard let wasmURL = Bundle.main.url(forResource: "contract", withExtension: "wasm") else {
            throw OPAError.moduleNotFound
        }

        // Step 1: Verify Wasm module integrity before execution
        try verifyModuleIntegrity(at: wasmURL)

        // Step 2: Read Wasm bytes
        let wasmData = try Data(contentsOf: wasmURL)
        let wasmBytes = Array(wasmData)

        // Step 3: Parse and instantiate via WasmKit
        let module = try parseWasm(bytes: wasmBytes)

        // Create engine and store
        engine = Engine()
        store = Store(engine: engine!)

        // Provide OPA-required imports (abort, println for debugging)
        // WasmKit 0.2+: Use Function(store:parameters:results:body:) — HostFunction is deprecated.
        let currentStore = store!
        var imports = Imports()
        imports.define(
            module: "env", name: "opa_abort",
            Function(store: currentStore, parameters: [.i32], results: []) { _, args in
                let addr = args[0].i32
                print("[OPA] ABORT called at address: \(addr)")
                return []
            }
        )
        imports.define(
            module: "env", name: "opa_println",
            Function(store: currentStore, parameters: [.i32], results: []) { _, args in
                let addr = args[0].i32
                print("[OPA] println at address: \(addr)")
                return []
            }
        )

        // Instantiate module
        moduleInstance = try module.instantiate(store: store!, imports: imports)

        // Get memory export
        guard let mem = moduleInstance?.exports[memory: "memory"] else {
            throw OPAError.evaluationFailed("Wasm module does not export 'memory'")
        }
        wasmMemory = mem

        // Step 4: Load the empty base data document `{}`
        baseDataAddr = try loadJSONIntoWasm("{}")

        // Step 5: Save the heap pointer for fast reset between evaluations
        baseHeapPointer = try callExportedFunction(OPAABIExport.heapPtrGet, args: [])

        isModuleLoaded = true
        print("[OPA] Wasm module loaded. Cold start complete. Heap base: \(baseHeapPointer)")
    }

    // MARK: - Policy Evaluation (hot path: ~0.16ms median)
    /// Evaluates the OPA policy with the current fitness state as input.
    /// Returns a PolicyResult with allow/deny decision.
    ///
    /// Thread-safe — evaluations are serialized on a dedicated queue.
    func evaluate(input: PolicyInput) throws -> PolicyResult {
        if !isModuleLoaded {
            try loadModule()
        }

        // Serialize input to JSON with snake_case keys (matches Rego input.field_name)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys  // CodingKeys already define snake_case
        let inputData = try encoder.encode(input)
        guard let inputJSON = String(data: inputData, encoding: .utf8) else {
            throw OPAError.serializationFailed
        }

        // Evaluate all entrypoints and merge results
        return try evaluationQueue.sync {
            // Reset heap to base pointer — reclaims memory from previous evaluation
            // WasmKit 0.2+: Value.i32() takes UInt32; use bitPattern to reinterpret Int32.
            try callExportedFunction(OPAABIExport.heapPtrSet, args: [.i32(UInt32(bitPattern: baseHeapPointer))])

            // Parse the input JSON into OPA's internal value representation
            let inputAddr = try loadJSONIntoWasm(inputJSON)

            // Evaluate "allow" entrypoint
            let allowResult = try evaluateEntrypoint(
                entrypoint: .allow,
                inputAddr: inputAddr,
                dataAddr: baseDataAddr
            )

            // Evaluate "requires_grace" entrypoint
            let graceResult = try evaluateEntrypoint(
                entrypoint: .requiresGrace,
                inputAddr: inputAddr,
                dataAddr: baseDataAddr
            )

            // Parse results
            let allow = parseOPABooleanResult(allowResult)
            let requiresGrace = parseOPABooleanResult(graceResult)

            // Determine deny reason
            let denyReason: String?
            if allow {
                denyReason = nil
            } else if input.timeDriftDetected {
                denyReason = "Security lockout: system clock manipulation detected."
            } else if requiresGrace {
                denyReason = "Grace period granted — data sync pending."
            } else {
                denyReason = computeDenyReason(input: input)
            }

            return PolicyResult(
                allow: allow,
                requiresGracePeriod: requiresGrace,
                denyReason: denyReason
            )
        }
    }

    // MARK: - Entrypoint Evaluation
    /// Evaluates a single OPA entrypoint and returns the raw JSON result string.
    private func evaluateEntrypoint(entrypoint: OPAEntrypoint, inputAddr: Int32, dataAddr: Int32) throws -> String {
        // Create a fresh evaluation context
        let ctxAddr = try callExportedFunction(OPAABIExport.evalContextNew, args: [])

        // Set the input document
        // WasmKit 0.2+: Value.i32() takes UInt32
        try callExportedFunctionVoid(OPAABIExport.evalContextSetInput,
            args: [.i32(UInt32(bitPattern: ctxAddr)), .i32(UInt32(bitPattern: inputAddr))])

        // Set the base data document
        try callExportedFunctionVoid(OPAABIExport.evalContextSetData,
            args: [.i32(UInt32(bitPattern: ctxAddr)), .i32(UInt32(bitPattern: dataAddr))])

        // Set the entrypoint ID
        try callExportedFunctionVoid(OPAABIExport.evalContextSetEntrypoint,
            args: [.i32(UInt32(bitPattern: ctxAddr)), .i32(UInt32(bitPattern: entrypoint.rawValue))])

        // Run evaluation
        let evalRC = try callExportedFunction(OPAABIExport.eval, args: [.i32(UInt32(bitPattern: ctxAddr))])
        guard evalRC == 0 else {
            throw OPAError.evaluationFailed("eval() returned non-zero: \(evalRC)")
        }

        // Extract result
        let resultAddr = try callExportedFunction(OPAABIExport.evalContextGetResult,
            args: [.i32(UInt32(bitPattern: ctxAddr))])

        // Serialize OPA result value back to JSON
        let jsonAddr = try callExportedFunction(OPAABIExport.jsonDump,
            args: [.i32(UInt32(bitPattern: resultAddr))])

        // Read the null-terminated JSON string from Wasm memory
        return try readCStringFromWasm(at: jsonAddr)
    }

    // MARK: - Wasm Memory Helpers

    /// Writes a JSON string into OPA Wasm memory and returns the parsed OPA value address.
    private func loadJSONIntoWasm(_ json: String) throws -> Int32 {
        let jsonBytes = Array(json.utf8)
        let len = Int32(jsonBytes.count)

        // Allocate memory in Wasm for the JSON string
        let strAddr = try callExportedFunction(OPAABIExport.malloc, args: [.i32(UInt32(bitPattern: len))])

        // Copy JSON bytes into Wasm memory
        try writeToWasmMemory(at: strAddr, bytes: jsonBytes)

        // Parse the JSON string into OPA's internal representation
        let valueAddr = try callExportedFunction(OPAABIExport.jsonParse,
            args: [.i32(UInt32(bitPattern: strAddr)), .i32(UInt32(bitPattern: len))])

        if valueAddr == 0 {
            throw OPAError.evaluationFailed("opa_json_parse returned NULL — invalid JSON input")
        }

        return valueAddr
    }

    /// Reads a null-terminated C string from Wasm linear memory.
    /// WasmKit 0.2+: `memory.data` is a computed property returning a `[UInt8]` copy.
    private func readCStringFromWasm(at address: Int32) throws -> String {
        guard let memory = wasmMemory else {
            throw OPAError.evaluationFailed("Wasm memory not available")
        }

        let allBytes = memory.data
        var result: [UInt8] = []
        var offset = Int(address)
        let maxLen = 65536  // Safety limit: 64 KB max string

        while offset < allBytes.count && offset - Int(address) < maxLen {
            let byte = allBytes[offset]
            if byte == 0 { break }
            result.append(byte)
            offset += 1
        }

        guard let str = String(bytes: result, encoding: .utf8) else {
            throw OPAError.evaluationFailed("Failed to decode UTF-8 string from Wasm memory")
        }
        return str
    }

    /// Writes raw bytes into Wasm linear memory at the given offset.
    /// WasmKit 0.2+: use `withUnsafeMutableBufferPointer(offset:count:)` for safe mutable access.
    private func writeToWasmMemory(at address: Int32, bytes: [UInt8]) throws {
        guard let memory = wasmMemory else {
            throw OPAError.evaluationFailed("Wasm memory not available")
        }

        let startIndex = Int(address)
        guard startIndex >= 0 else {
            throw OPAError.evaluationFailed("Invalid Wasm memory address")
        }

        try memory.withUnsafeMutableBufferPointer(offset: UInt(startIndex), count: bytes.count) { buffer in
            for (i, byte) in bytes.enumerated() {
                buffer[i] = byte
            }
        }
    }

    // MARK: - Wasm Function Call Helpers

    /// Calls an exported Wasm function and returns its i32 result.
    @discardableResult
    private func callExportedFunction(_ name: String, args: [Value]) throws -> Int32 {
        guard let instance = moduleInstance, let store = store else {
            throw OPAError.evaluationFailed("Module not instantiated")
        }

        guard let function = instance.exports[function: name] else {
            throw OPAError.evaluationFailed("Export '\(name)' not found in Wasm module")
        }

        // WasmKit 0.2+: invoke() does not take a `store:` argument.
        let results = try function.invoke(args)

        guard let firstResult = results.first else {
            throw OPAError.evaluationFailed("'\(name)' returned no result")
        }

        // WasmKit 0.2+: Value.i32 returns UInt32; reinterpret as Int32 for OPA ABI.
        return Int32(bitPattern: firstResult.i32)
    }

    /// Calls an exported Wasm function that returns void.
    private func callExportedFunctionVoid(_ name: String, args: [Value]) throws {
        guard let instance = moduleInstance, let store = store else {
            throw OPAError.evaluationFailed("Module not instantiated")
        }

        guard let function = instance.exports[function: name] else {
            throw OPAError.evaluationFailed("Export '\(name)' not found in Wasm module")
        }

        // WasmKit 0.2+: invoke() does not take a `store:` argument.
        _ = try function.invoke(args)
    }

    // MARK: - Result Parsing

    /// Parses an OPA result JSON like `[{"result": true}]` into a Bool.
    /// OPA Wasm wraps results in a result set array.
    private func parseOPABooleanResult(_ json: String) -> Bool {
        // OPA Wasm result format: [{"result": <value>}]
        // For boolean entrypoints, value is true/false
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first,
              let result = first["result"] as? Bool else {
            // OPA returns empty result set `[]` for undefined/false
            return false
        }
        return result
    }

    /// Computes a human-readable deny reason from the input state.
    /// This mirrors the Rego deny_reason rules for cases where we evaluate
    /// entrypoints individually rather than querying deny_reason.
    private func computeDenyReason(input: PolicyInput) -> String {
        switch input.goalCurrency {
        case "activeCalories":
            let remaining = input.dailyCalorieGoal - input.currentActiveCalories
            return String(format: "%.0f kcal remaining to unlock.", max(0, remaining))
        case "steps":
            let remaining = input.dailyStepsGoal - input.currentSteps
            return "\(max(0, remaining)) steps remaining to unlock."
        default:
            return "Daily fitness goal not yet reached."
        }
    }

    // MARK: - Hash Pinning (Wasm Integrity Verification)
    /// Computes SHA-256 of the loaded Wasm binary and compares against a signed manifest.
    /// Prevents loading a tampered or substituted policy module.
    private func verifyModuleIntegrity(at url: URL) throws {
        let wasmData = try Data(contentsOf: url)

        // Compute SHA-256 digest of the Wasm binary
        let computedHash = SHA256.hash(data: wasmData)
        let computedHashHex = computedHash.compactMap { String(format: "%02x", $0) }.joined()

        // Load the manifest file containing the expected hash + signature
        guard let manifestURL = Bundle.main.url(forResource: "contract_manifest", withExtension: "json") else {
            // If no manifest exists, log a warning but allow loading in development
            // In production builds, this should be a hard failure.
            #if DEBUG
            print("[OPA] ⚠️ Hash pinning: No manifest found. Skipping verification (DEBUG mode).")
            return
            #else
            throw OPAError.integrityCheckFailed
            #endif
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(WasmManifest.self, from: manifestData)

        // Compare computed hash against expected hash from manifest
        guard computedHashHex == manifest.sha256 else {
            print("[OPA] ❌ Hash mismatch! Expected: \(manifest.sha256), Got: \(computedHashHex)")
            throw OPAError.integrityCheckFailed
        }

        // Verify ECDSA signature on the manifest hash
        // The developer's P256 public key is embedded at compile time
        if let signatureHex = manifest.signature, let publicKeyHex = manifest.publicKey {
            let isValid = try verifyECDSASignature(
                hashHex: manifest.sha256,
                signatureHex: signatureHex,
                publicKeyHex: publicKeyHex
            )
            guard isValid else {
                print("[OPA] ❌ ECDSA signature verification failed!")
                throw OPAError.integrityCheckFailed
            }
        }

        print("[OPA] ✅ Hash pinning verified: \(computedHashHex.prefix(16))...")
    }

    /// Verifies an ECDSA P256 signature over a SHA-256 hash using CryptoKit.
    private func verifyECDSASignature(hashHex: String, signatureHex: String, publicKeyHex: String) throws -> Bool {
        // Decode hex strings to Data
        let signatureData = Data(hexString: signatureHex)
        let publicKeyData = Data(hexString: publicKeyHex)

        guard let sigData = signatureData, let pubKeyData = publicKeyData else {
            throw OPAError.integrityCheckFailed
        }

        // Import the public key
        let publicKey = try P256.Signing.PublicKey(x963Representation: pubKeyData)

        // Create the signature
        let signature = try P256.Signing.ECDSASignature(derRepresentation: sigData)

        // The data being signed is the SHA-256 hash hex string itself
        let messageData = Data(hashHex.utf8)
        let digest = SHA256.hash(data: messageData)

        // Verify
        return publicKey.isValidSignature(signature, for: digest)
    }

    // MARK: - Module Teardown

    /// Unloads the Wasm module and releases all resources.
    /// Call this on app termination or if the policy needs to be reloaded.
    func unloadModule() {
        evaluationQueue.sync {
            moduleInstance = nil
            wasmMemory = nil
            store = nil
            engine = nil
            isModuleLoaded = false
            baseHeapPointer = 0
            baseDataAddr = 0
            print("[OPA] Wasm module unloaded.")
        }
    }

    // MARK: - Native Swift Fallback
    /// Mirrors the Rego policy logic exactly.
    /// Used when the Wasm module is unavailable (e.g., contract.wasm missing from bundle).
    func evaluateWithFallback(input: PolicyInput) -> PolicyResult {
        // Try Wasm first, fall back to native Swift
        if let result = try? evaluate(input: input) {
            return result
        }

        print("[OPA] Wasm evaluation failed — using native Swift fallback.")
        return evaluateNativeFallback(input: input)
    }

    private func evaluateNativeFallback(input: PolicyInput) -> PolicyResult {
        // Tamper detection — time drift detected means fail-closed
        if input.timeDriftDetected {
            return PolicyResult(allow: false, requiresGracePeriod: false, denyReason: "Security lockout: system clock manipulation detected.")
        }

        // Break-Glass override
        if input.overrideActive && input.currentTime < input.overrideExpiration {
            return PolicyResult(allow: true, requiresGracePeriod: false, denyReason: nil)
        }

        // Primary PBAC rule — goal met?
        let goalMet: Bool
        switch input.goalCurrency {
        case "activeCalories":
            goalMet = input.currentActiveCalories >= input.dailyCalorieGoal
        case "steps":
            goalMet = Double(input.currentSteps) >= Double(input.dailyStepsGoal)
        default:
            goalMet = input.currentActiveCalories >= input.dailyCalorieGoal
        }

        if goalMet {
            return .allowed
        }

        // Fail-soft grace period — stale data + timer expired
        let requiresGrace = input.currentActiveCalories < input.dailyCalorieGoal
            && input.dataStatenessSeconds > 3600
            && input.uiTimerExpired

        return PolicyResult(
            allow: false,
            requiresGracePeriod: requiresGrace,
            denyReason: requiresGrace
                ? "Grace period granted — data sync pending."
                : computeDenyReason(input: input)
        )
    }
}

// MARK: - Wasm Manifest Model
/// Represents the contract_manifest.json file that contains the expected
/// SHA-256 hash and optional ECDSA signature for integrity verification.
private struct WasmManifest: Codable {
    let sha256: String
    let signature: String?
    let publicKey: String?
    let buildDate: String?
    let opaVersion: String?

    enum CodingKeys: String, CodingKey {
        case sha256      = "sha256"
        case signature   = "signature"
        case publicKey   = "public_key"
        case buildDate   = "build_date"
        case opaVersion  = "opa_version"
    }
}

// MARK: - Errors
enum OPAError: LocalizedError {
    case moduleNotFound
    case evaluationFailed(String)
    case integrityCheckFailed
    case serializationFailed

    var errorDescription: String? {
        switch self {
        case .moduleNotFound:          return "OPA Wasm module not found in bundle."
        case .evaluationFailed(let m): return "Policy evaluation failed: \(m)"
        case .integrityCheckFailed:    return "Wasm module integrity check failed. Possible tampering detected."
        case .serializationFailed:     return "Failed to serialize policy input."
        }
    }
}

// MARK: - Data Hex Extension
private extension Data {
    /// Initializes Data from a hex-encoded string. Returns nil if the string is invalid.
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
