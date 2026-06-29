// Services/EmailCredentialStore.swift
// Local password store for the email/password sign-up + sign-in flow.
//
// Without a backend we can't do real password verification across devices, so
// we store a per-account salted SHA-256 password hash in the iOS Keychain. This
// proves "the same person who signed up on this device is signing back in" and
// protects the password against simple backup snooping (kSecAttrAccessible
// is set to `WhenUnlockedThisDeviceOnly`).
//
// For cross-device login users should use Sign in with Apple (handled in
// `AuthManager.handleAppleCredential`).

import Foundation
import CryptoKit
import Security

enum EmailCredentialError: LocalizedError {
    case keychainStoreFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case noAccount
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .keychainStoreFailed(let s):
            return "Couldn't save credentials (Keychain \(s)). Try again."
        case .keychainReadFailed(let s):
            return "Couldn't read credentials (Keychain \(s)). Try again."
        case .noAccount:
            return "We couldn't find an account with that username on this device. Sign up first."
        case .wrongPassword:
            return "Wrong password. Try again or use Sign in with Apple."
        }
    }
}

/// On-disk record stored in Keychain (one per email).
private struct EmailCredentialRecord: Codable {
    let appleUserID: String
    let email: String
    let salt: Data
    let passwordHash: Data
    let createdAt: Date
}

@MainActor
enum EmailCredentialStore {

    private static let service = "com.sweat2scroll.emailCredentials"

    // MARK: - Public API

    /// Stable per-email account ID we use as the `appleUserID` slot for email
    /// sign-ups so the rest of the app (`CloudUserAccount`, audit log, pairing)
    /// keeps working unchanged.
    static func appleUserID(forEmail email: String) -> String {
        let normalized = normalize(email)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "email_\(hex.prefix(32))"
    }

    /// True when we already have credentials for this email on this device.
    static func hasAccount(email: String) -> Bool {
        (try? load(email: normalize(email))) != nil
    }

    /// Persist a new email/password credential. Overwrites any previous entry
    /// for this email so users can re-sign up after wiping the app.
    @discardableResult
    static func register(email: String, password: String) throws -> String {
        let email = normalize(email)
        var saltBytes = Data(count: 16)
        let status = saltBytes.withUnsafeMutableBytes { ptr -> Int32 in
            guard let baseAddress = ptr.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, 16, baseAddress)
        }
        guard status == errSecSuccess else {
            throw EmailCredentialError.keychainStoreFailed(status)
        }
        let appleUserID = appleUserID(forEmail: email)
        let hash = derive(password: password, salt: saltBytes)
        let record = EmailCredentialRecord(
            appleUserID: appleUserID,
            email: email,
            salt: saltBytes,
            passwordHash: hash,
            createdAt: Date()
        )
        try save(record)
        return appleUserID
    }

    /// Verify `password` against stored credentials. Returns the appleUserID on
    /// success.
    static func verify(email: String, password: String) throws -> String {
        let email = normalize(email)
        guard let record = try load(email: email) else {
            throw EmailCredentialError.noAccount
        }
        let candidate = derive(password: password, salt: record.salt)
        guard candidate == record.passwordHash else {
            throw EmailCredentialError.wrongPassword
        }
        return record.appleUserID
    }

    /// Wipe all locally stored email credentials (used by sign-out/dev tools).
    static func wipe() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Internals

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func derive(password: String, salt: Data) -> Data {
        var input = Data()
        input.append(salt)
        input.append(Data(password.utf8))
        let digest = SHA256.hash(data: input)
        return Data(digest)
    }

    private static func save(_ record: EmailCredentialRecord) throws {
        let data = try JSONEncoder().encode(record)
        let baseQuery: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  record.email
        ]
        let attrs: [String: Any] = [
            kSecValueData as String:    data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var insert = baseQuery
        insert.merge(attrs) { _, new in new }
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EmailCredentialError.keychainStoreFailed(status)
        }
    }

    private static func load(email: String) throws -> EmailCredentialRecord? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  email,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw EmailCredentialError.keychainReadFailed(status)
        }
        return try JSONDecoder().decode(EmailCredentialRecord.self, from: data)
    }
}
