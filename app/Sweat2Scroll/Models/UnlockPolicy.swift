// Models/UnlockPolicy.swift
// Represents the input/output contract for the Wasm OPA policy engine.
// Input is serialized to JSON and passed to the Wasm runtime.
// Output is deserialized from the Wasm evaluation result.

import Foundation

// MARK: - Wasm Policy Input
// Matches the `input` object expected by fitness_policy.rego
struct PolicyInput: Codable {
    var currentActiveCalories: Double
    var currentSteps: Int
    var dailyCalorieGoal: Double
    var dailyStepsGoal: Int
    var goalCurrency: String          // "activeCalories" | "steps"
    var overrideActive: Bool
    var overrideExpiration: TimeInterval   // Unix timestamp
    var currentTime: TimeInterval          // Unix timestamp
    var dataStatenessSeconds: TimeInterval
    var uiTimerExpired: Bool
    var timeDriftDetected: Bool

    enum CodingKeys: String, CodingKey {
        case currentActiveCalories   = "current_active_calories"
        case currentSteps            = "current_steps"
        case dailyCalorieGoal        = "daily_calorie_goal"
        case dailyStepsGoal          = "daily_steps_goal"
        case goalCurrency            = "goal_currency"
        case overrideActive          = "override_active"
        case overrideExpiration      = "override_expiration"
        case currentTime             = "current_time"
        case dataStatenessSeconds    = "data_staleness_seconds"
        case uiTimerExpired          = "ui_timer_expired"
        case timeDriftDetected       = "time_drift_detected"
    }
}

// MARK: - Wasm Policy Output
// Fields returned by the OPA policy evaluation
struct PolicyResult: Codable {
    var allow: Bool
    var requiresGracePeriod: Bool
    var denyReason: String?

    enum CodingKeys: String, CodingKey {
        case allow
        case requiresGracePeriod = "requires_grace_period"
        case denyReason          = "deny_reason"
    }

    static let denied = PolicyResult(allow: false, requiresGracePeriod: false, denyReason: "Goal not met")
    static let allowed = PolicyResult(allow: true, requiresGracePeriod: false, denyReason: nil)
}

// MARK: - Override State
struct OverrideState: Codable {
    var isActive: Bool
    var expiresAt: Date
    var grantedByPartner: String   // Partner's display name
    var grantReason: String?

    var isValid: Bool {
        isActive && Date() < expiresAt
    }

    static let inactive = OverrideState(
        isActive: false,
        expiresAt: .distantPast,
        grantedByPartner: "",
        grantReason: nil
    )
}
