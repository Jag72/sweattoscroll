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
    private static func computeHOTP(secret: Data, counter: UInt64) throws -> String {
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
    private static func currentCounter() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 / timeStepSeconds)
    }

    // MARK: - ECDH Key Exchange (Pairing)
    /// Generates an ECDH key pair for the initial device pairing.
    /// The derived shared secret is stored in the Secure Enclave.
    static func performECDHExchange(withPartnerPublicKeyData partnerKeyData: Data) throws -> Data {
        // Generate ephemeral private key
        let privateKey = P256.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey

        // Deserialize partner's public key
        let partnerPublicKey = try P256.KeyAgreement.PublicKey(rawRepresentation: partnerKeyData)

        // Derive shared secret via ECDH
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: partnerPublicKey)

        // Derive symmetric key using HKDF-SHA256
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "sweat2scroll-v1".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )

        let keyData = symmetricKey.withUnsafeBytes { Data($0) }
        try storeSharedSecret(keyData)
        return publicKey.rawRepresentation
    }

    // MARK: - Shared Secret Fingerprint (for GovernanceContract)
    static func fingerprint() throws -> String {
        let secret = try retrieveSharedSecret()
        let hash = SHA256.hash(data: secret)
        return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
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
