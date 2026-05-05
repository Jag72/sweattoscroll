// AppSession.swift
// PRD v2: session marker + dev credentials (simulator). Apple Sign In sets token on success.

import Foundation

enum AppSession {
    static let sessionTokenKey = "sessionToken"
    /// Non-nil after successful Sign in with Apple or dev login (PRD `puji` / `1234`).
    static var hasSessionToken: Bool {
        guard let t = UserDefaults.standard.string(forKey: sessionTokenKey), !t.isEmpty else { return false }
        return true
    }

    static func setAuthenticated() {
        UserDefaults.standard.set("s2s_ok", forKey: sessionTokenKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: sessionTokenKey)
    }

    // MARK: - PRD dev / simulator (do not use in production builds for real auth)
    static let devUsername = "puji"
    static let devPassword = "1234"
    static let devOTP = "1234"

    static func isDevCredentialMatch(username: String, password: String) -> Bool {
        username == devUsername && password == devPassword
    }
}
