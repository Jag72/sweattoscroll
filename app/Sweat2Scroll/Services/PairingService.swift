// Services/PairingService.swift
// Cross-account 6-digit pairing that ALSO performs the ECDH key exchange:
//
//   Monitor  generateCode()            → makes ECDH keypair, publishes public key
//                                         + 6-digit code to the PUBLIC CloudKit DB.
//   User     validateAndPair(code)     → reads monitor's public key, derives the
//                                         shared TOTP secret, writes its own public
//                                         key back, links its own account.
//   Monitor  pollForPairingConfirmation → reads user's public key, derives the
//                                         SAME shared secret, links its own account.
//
// After this, both devices hold the same 256-bit secret in the Keychain, so the
// emergency-override OTP (30-second rotating TOTP) can be generated and validated
// entirely offline — CloudKit is only needed for this one-time handshake.
//
// Each device writes ONLY its own UserAccount (private DB) — no cross-account
// writes — so pairing works between two real, different iCloud accounts.

import Foundation
import CloudKit

@MainActor
final class PairingService: ObservableObject {
    static let shared = PairingService()

    private let cloud = CloudKitService.shared
    private let auth = AuthManager.shared
    /// Pairing codes are meant to be typed within a few minutes of generation.
    private let codeTTL: TimeInterval = 600   // 10 minutes to complete pairing

    // MARK: - Monitor: generate code + publish public key

    /// Generates a random 6-digit code, an ECDH keypair, and publishes both
    /// (code + monitor public key) to the public DB so the user's device can
    /// read them. Returns the code to display.
    func generateCode(forMonitorID monitorAppleUserID: String,
                      monitorDisplayName: String) async throws -> String {
        let monitorPublicKey = try TOTPService.beginPairingAsMonitor()
        let code = String(format: "%06d", Int.random(in: 100_000...999_999))
        let expires = Date().addingTimeInterval(codeTTL)
        try await cloud.savePairHandshake(
            code: code,
            monitorUserID: monitorAppleUserID,
            monitorPublicKey: monitorPublicKey,
            monitorDisplayName: monitorDisplayName,
            expiresAt: expires
        )
        return code
    }

    /// Strips non-digits and returns the value iff it's exactly 6 digits.
    /// Static so tests can verify input handling without CloudKit.
    static func normalizeCode(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        return digits.count == 6 ? digits : nil
    }

    // MARK: - User: validate code + derive shared secret

    /// Reads the monitor's handshake, derives + stores the shared TOTP secret,
    /// writes our public key back, and links THIS device's account to the
    /// monitor. Returns `.success(linkedMonitorID:)` on success.
    func validateAndPair(code: String,
                         userAppleUserID: String,
                         userDisplayName: String) async throws -> PairingResult {
        guard let normalized = Self.normalizeCode(code) else { return .invalid }

        guard let handshake = await cloud.fetchPairHandshake(code: normalized) else {
            return .invalid       // missing or expired
        }
        guard !handshake.monitorPublicKey.isEmpty,
              !handshake.monitorUserID.isEmpty else { return .invalid }
        // Can't pair with yourself.
        if handshake.monitorUserID == userAppleUserID { return .invalid }

        // Derive + store the shared secret; get our own public key back.
        let response: (ownPublicKeyBase64: String, fingerprint: String)
        do {
            response = try TOTPService.completePairingAsUser(
                monitorPublicKeyBase64: handshake.monitorPublicKey)
        } catch {
            return .invalid       // malformed key
        }

        // Publish our public key (in our OWN record) so the monitor can derive
        // the same secret.
        try await cloud.writePairResponse(
            code: normalized,
            userUserID: userAppleUserID,
            userPublicKey: response.ownPublicKeyBase64,
            userDisplayName: userDisplayName
        )

        // Link OUR OWN account only (private DB write to our own record).
        await linkLocalAccount(peerID: handshake.monitorUserID,
                               peerName: handshake.monitorDisplayName)

        return .success(linkedMonitorID: handshake.monitorUserID)
    }

    // MARK: - Monitor: poll for the user's response + finish key exchange

    /// Polls the handshake record for the user's public key. When it appears,
    /// derives the SAME shared secret, links this device's account, cleans up,
    /// and returns true. Times out after 5 minutes.
    func pollForPairingConfirmation(monitorAppleUserID: String, code: String) async -> Bool {
        guard let normalized = Self.normalizeCode(code) else { return false }
        let deadline = Date().addingTimeInterval(300)

        while Date() < deadline {
            if let response = await cloud.fetchPairResponse(code: normalized) {
                // Derive the matching shared secret from the user's public key.
                do {
                    _ = try TOTPService.completePairingAsMonitor(
                        userPublicKeyBase64: response.userPublicKey)
                } catch {
                    return false
                }
                await linkLocalAccount(peerID: response.userUserID,
                                       peerName: response.userDisplayName)
                await cloud.deletePairHandshake(code: normalized)   // clean up our own record
                return true
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)  // poll every 3s
        }
        return false
    }

    // MARK: - Local account linking (own record only)

    /// Marks THIS device's own CloudUserAccount as paired to `peerID`. Never
    /// touches the peer's record — that's what made cross-account pairing fail.
    private func linkLocalAccount(peerID: String, peerName: String?) async {
        guard var acc = auth.cachedAccount else { return }
        acc.isPaired = true
        acc.linkedPeerAppleUserID = peerID
        if let name = peerName, !name.isEmpty, (acc.relationshipLabel ?? "").isEmpty {
            acc.relationshipLabel = name
        }
        if !auth.isDevSession {
            try? await cloud.saveUserAccount(acc)
        }
        auth.updateCachedAccount(acc)
    }
}
