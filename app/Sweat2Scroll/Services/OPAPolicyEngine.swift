// Services/OPAPolicyEngine.swift
// Thin facade over existing OPA / Wasm evaluation (`OPAService` + `ActivityViewModel`).
// Call from dashboards after HealthKit sync when you want an explicit policy pass.

import Foundation

enum OPAPolicyEngine {
    /// Reserved for explicit re-evaluation hooks (dashboard pull-to-refresh, etc.).
    static func noteDashboardAppeared() {
        // `ActivityViewModel` already runs a periodic evaluation loop.
    }
}
