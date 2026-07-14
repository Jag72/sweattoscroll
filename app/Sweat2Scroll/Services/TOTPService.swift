// Services/TOTPService.swift
// Implements TOTP (RFC 6238) using CryptoKit + Secure Enclave.
// Used for the Break-Glass Protocol emergency access override.
// The shared 256-bit secret is stored in the Secure Enclave during pairing.
// Supports ±1 time-step drift tolerance for clock desynchronization.

import Foundation
import CryptoKit
import Security

class TOTPService {

    // MARK: - Constants
    static let timeStepSeconds: Double = 30     // Standard TOTP period
    static let digits: Int = 6                  // 6-digit OTP
    static let driftTolerance: Int = 1          // ±1 period tolerance

    // MARK: - Keychain Tag for Shared Secret
    private static let secretKeychainTag = "com.sweat2scroll.sharedSecret"

    // MARK: - Store Shared Secret in Keychain (Secure Enclave)
    /// Called once during device pairing after ECDH key exchange.
    /// Stores the derived 256-bit symmetric secret with Secure Enclave protection.
    static func storeSharedSecret(_ secretData: Data) throws {
        let query: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrAccount as String:         secretKeychainTag,
            kSecValueData as String:           secretData,
            // Only accessible when device is unlocked — prevents backup extraction
            kSecAttrAccessible as String:      kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary) // Remove any existing entry
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TOTPError.keychainStoreFailed(status)
        }
    }

    // MARK: - Retrieve Shared Secret from Keychain
    static func retrieveSharedSecret() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrAccount as String:        secretKeychainTag,
            kSecReturnData as String:         true,
            kSecMatchLimit as String:         kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let secretData = result as? Data else {
            throw TOTPError.keychainRetrieveFailed(status)
        }
        return secretData
    }

    // MARK: - Generate TOTP (Controller — Partner B)
    /// Generates the current 6-digit TOTP code using the shared secret.
    static func generateCode() throws -> String {
        let secret = try retrieveSharedSecret()
        let counter = currentCounter()
        return try computeHOTP(secret: secret, counter: counter)
    }

    // MARK: - Validate TOTP (Controlled — Partner A)
    /// Validates a 6-digit code with ±1 time-step drift tolerance.
    static func validateCode(_ inputCode: String) throws -> Bool {
        let secret = try retrieveSharedSecret()
        let currentCounter = currentCounter()

        // Check current counter ± drift tolerance
        for drift in -driftTolerance...driftTolerance {
            let counter = UInt64(Int64(currentCounter) + Int64(drift))
            let expectedCode = try computeHOTP(secret: secret, counter: counter)
            if expectedCode == inputCode {
                return true
            }
        }
        return false
    }

    // MARK: - HOTP Core (HMAC-SHA1 per RFC 4226, TOTP uses HMAC-SHA256)
    /// Internal access (was `private`) so XCTest can verify RFC 6238 / RFC 4226
    /// conformance against well-known vectors without going through the
    /// keychain-backed `generateCode()` / `validateCode()` path. Production
    /// callers should still use the keychain-backed wrappers — there is no
    /// reason for app code to call this directly.
    static func computeHOTP(secret: Data, counter: UInt64) throws -> String {
        // Convert counter to big-endian 8-byte array
        var bigEndianCounter = counter.bigEndian
        let counterData = withUnsafeBytes(of: &bigEndianCounter) { Data($0) }

        // Compute HMAC-SHA256
        let symmetricKey = SymmetricKey(data: secret)
        let hmac = HMAC<SHA256>.authenticationCode(for: counterData, using: symmetricKey)
        let hmacData = Data(hmac)

        // Dynamic truncation
        let offset = Int(hmacData[hmacData.count - 1] & 0x0F)
        let truncatedValue = hmacData.withUnsafeBytes { bytes -> UInt32 in
            var value: UInt32 = 0
            value |= UInt32(bytes[offset])     << 24
            value |= UInt32(bytes[offset + 1]) << 16
            value |= UInt32(bytes[offset + 2]) << 8
            value |= UInt32(bytes[offset + 3])
            return value & 0x7FFFFFFF
        }

        // Extract digits
        let otp = truncatedValue % UInt32(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)d", otp)
    }

    // MARK: - Current TOTP Counter
    /// Internal so tests can verify the counter math against synthetic dates.
    static func currentCounter(at date: Date = Date()) -> UInt64 {
        UInt64(date.timeIntervalSince1970 / timeStepSeconds)
    }

    // MARK: - ECDH Key Exchange (Responder side)
    /// Generates a FRESH ephemeral keypair, derives the shared secret from the
    /// partner's public key, stores it in the Keychain, and returns our own
    /// public key (raw representation) so the partner can derive the same secret.
    /// Used by the user (responder) side of pairing via `completePairingAsUser`.
    static func performECDHExchange(withPartnerPublicKeyData partnerKeyData: Data) throws -> Data {
        let privateKey = P256.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey

        let partnerPublicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: partnerKeyData)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: partnerPublicKey)

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "sweat2scroll-v1".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )

        try storeSharedSecret(symmetricKey.withUnsafeBytes { Data($0) })
        return publicKey.rawRepresentation
    }

    // MARK: - Shared Secret Fingerprint (for GovernanceContract)
    static func fingerprint() throws -> String {
        let secret = try retrieveSharedSecret()
        let hash = SHA256.hash(data: secret)
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Two-Sided Pairing Handshake (6-digit code carries the ECDH keys)
    //
    // The bug this fixes: the old QR flow called `performECDHExchange(...)` on
    // BOTH devices, and that function always generated a *fresh* private key.
    // So each side computed a different secret (A2·B1 vs A1·B1) and no TOTP the
    // monitor generated could ever validate on the user's device.
    //
    // New flow, driven by the existing 6-digit pairing code:
    //   1. Monitor: `beginPairingAsMonitor()` → makes ONE keypair, persists the
    //      private half in the Keychain, returns its public key (goes into the
    //      PairCode record on the public DB).
    //   2. User: `completePairingAsUser(monitorPublicKeyBase64:)` → makes its own
    //      keypair, derives + stores the shared secret, returns its public key
    //      (written back into the same PairCode record).
    //   3. Monitor polls, sees the user's public key, and calls
    //      `completePairingAsMonitor(userPublicKeyBase64:)` — which reuses the
    //      SAME private key from step 1 to derive the identical shared secret.
    //
    // Both sides now hold the same 256-bit secret; TOTP works offline forever
    // after (no CloudKit needed to generate or validate override codes).

    private static let pairingPrivKeyTag = "com.sweat2scroll.pairingEphemeralPriv"

    /// Monitor side, step 1. Generates the ephemeral ECDH keypair, stores the
    /// private key in the Keychain, and returns the public key (Base64) to embed
    /// in the pairing record.
    static func beginPairingAsMonitor() throws -> String {
        let privateKey = P256.KeyAgreement.PrivateKey()
        try storeGeneric(privateKey.rawRepresentation, tag: pairingPrivKeyTag)
        return privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    /// User side, step 2. Fresh keypair → derive + store shared secret →
    /// return own public key (Base64) so the monitor can derive the same secret.
    @discardableResult
    static func completePairingAsUser(monitorPublicKeyBase64: String) throws -> (ownPublicKeyBase64: String, fingerprint: String) {
        guard let monitorKeyData = Data(base64Encoded: monitorPublicKeyBase64) else {
            throw TOTPError.keyExchangeFailed
        }
        // performECDHExchange makes a fresh key, derives the secret, stores it,
        // and returns our own public key — exactly the responder behavior.
        let ownPub = try performECDHExchange(withPartnerPublicKeyData: monitorKeyData)
        return (ownPub.base64EncodedString(), try fingerprint())
    }

    /// Monitor side, step 3. Reuses the private key stored in step 1 to derive
    /// the identical shared secret from the user's public key.
    @discardableResult
    static func completePairingAsMonitor(userPublicKeyBase64: String) throws -> String {
        guard let privData = try loadGeneric(tag: pairingPrivKeyTag),
              let privateKey = try? P256.KeyAgreement.PrivateKey(rawRepresentation: privData) else {
            throw TOTPError.keyExchangeFailed
        }
        guard let userKeyData = Data(base64Encoded: userPublicKeyBase64),
              let userPublicKey = try? P256.KeyAgreement.PublicKey(rawRepresentation: userKeyData) else {
            throw TOTPError.keyExchangeFailed
        }
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: userPublicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "sweat2scroll-v1".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )
        try storeSharedSecret(symmetricKey.withUnsafeBytes { Data($0) })
        deleteGeneric(tag: pairingPrivKeyTag)   // one-time use
        return try fingerprint()
    }

    /// True once a shared secret exists (i.e. the device is paired for overrides).
    static var hasSharedSecret: Bool {
        (try? retrieveSharedSecret()) != nil
    }

    /// Wipes the shared secret + any dangling ephemeral private key (unpair).
    static func clearPairingSecrets() {
        for tag in [secretKeychainTag, pairingPrivKeyTag] {
            let q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: tag
            ]
            SecItemDelete(q as CFDictionary)
        }
    }

    // MARK: - Generic Keychain helpers (ephemeral pairing private key)

    private static func storeGeneric(_ data: Data, tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TOTPError.keychainStoreFailed(status) }
    }

    private static func loadGeneric(tag: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TOTPError.keychainRetrieveFailed(status) }
        return result as? Data
    }

    private static func deleteGeneric(tag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tag
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors
enum TOTPError: LocalizedError {
    case keychainStoreFailed(OSStatus)
    case keychainRetrieveFailed(OSStatus)
    case invalidCode
    case keyExchangeFailed

    var errorDescription: String? {
        switch self {
        case .keychainStoreFailed(let s):    return "Keychain store failed: \(s)"
        case .keychainRetrieveFailed(let s): return "Keychain retrieve failed: \(s)"
        case .invalidCode:                   return "Invalid or expired OTP code."
        case .keyExchangeFailed:             return "ECDH key exchange failed."
        }
    }
}
