// Services/BiometricAuthService.swift
// Face ID / Touch ID gate for restoring a saved session on cold launch.
//
// Behavior: when the app is relaunched (including after iOS terminated it in
// the background) with a saved session, the user is asked to unlock with
// Face ID / Touch ID instead of retyping their password. If biometrics are
// unavailable or not enrolled, the gate is skipped entirely — it must never
// lock a user out of their own session.

import Foundation
import LocalAuthentication

@MainActor
final class BiometricAuthService {

    static let shared = BiometricAuthService()
    private init() {}

    /// User preference key — toggled from the Profile screen.
    static let lockEnabledKey = "faceIDLockEnabled"

    enum BiometryKind {
        case faceID, touchID, none

        var label: String {
            switch self {
            case .faceID:  return "Face ID"
            case .touchID: return "Touch ID"
            case .none:    return "Passcode"
            }
        }

        var systemImage: String {
            switch self {
            case .faceID:  return "faceid"
            case .touchID: return "touchid"
            case .none:    return "lock.fill"
            }
        }
    }

    /// What the device supports right now (enrolled and permitted).
    var availableBiometry: BiometryKind {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch ctx.biometryType {
        case .faceID:  return .faceID
        case .touchID: return .touchID
        default:       return .none
        }
    }

    /// Whether the cold-launch lock should be shown: user has it enabled
    /// (default ON) and the device can actually authenticate.
    var shouldGateOnLaunch: Bool {
        let enabled = UserDefaults.standard.object(forKey: Self.lockEnabledKey) as? Bool ?? true
        return enabled && availableBiometry != .none
    }

    /// Prompts Face ID / Touch ID with passcode fallback.
    /// Returns true on success. Returns true immediately if the device has no
    /// auth capability at all (never brick the session behind a missing sensor).
    func authenticate(reason: String = "Unlock Sweat2Scroll and restore your session") async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Use Password Instead"

        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            AppLogger.auth.warning("Biometric gate skipped — no auth available: \(error?.localizedDescription ?? "n/a", privacy: .public)")
            return true
        }

        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            AppLogger.auth.info("Biometric unlock cancelled/failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
