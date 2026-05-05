// SecurityGate.swift
// PRD §4B: Face ID / passcode before adding or removing pairing from the menu.

import Foundation
import LocalAuthentication

enum SecurityGate {
    /// Prompts biometrics or device passcode. Simulator may use passcode fallback.
    @MainActor
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            return false
        }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
