// Models/ActivityGoal.swift
// Represents the negotiated daily fitness contract between two Mutual Controllers.

import Foundation

enum GoalCurrency: String, Codable, CaseIterable {
    case activeCalories = "Active Calories"
    case steps          = "Steps"

    /// Machine-readable identifier used in OPA policy input and QR pairing payloads.
    var codeName: String {
        switch self {
        case .activeCalories: return "activeCalories"
        case .steps:          return "steps"
        }
    }

    /// Initializes from a codeName string (e.g., "activeCalories" or "steps").
    /// Falls back to parsing the display rawValue.
    static func fromCodeName(_ name: String) -> GoalCurrency {
        switch name {
        case "activeCalories": return .activeCalories
        case "steps":          return .steps
        default:               return GoalCurrency(rawValue: name) ?? .activeCalories
        }
    }
}

struct ActivityGoal: Codable, Identifiable {
    var id: UUID = UUID()

    var currency: GoalCurrency

    // The CDC-recommended target (computed by CalorieEngine)
    var recommendedTarget: Double

    // The final agreed target (Controller may adjust within safe bounds)
    var agreedTarget: Double

    // Hard safety caps per age cohort (enforced at architecture level)
    var hardCap: Double

    // Progress today
    var currentProgress: Double = 0

    var progressFraction: Double {
        guard agreedTarget > 0 else { return 0 }
        return min(currentProgress / agreedTarget, 1.0)
    }

    var isUnlocked: Bool {
        guard agreedTarget > 0 else { return false }
        return currentProgress >= agreedTarget
    }

    var remaining: Double {
        max(agreedTarget - currentProgress, 0)
    }

    // Staleness — seconds since last HealthKit sample
    var lastSampleTimestamp: Date = .distantPast
    var dataStalenesSeconds: TimeInterval {
        Date().timeIntervalSince(lastSampleTimestamp)
    }

    // Is data considered stale (> 1 hour since last sample)
    var isDataStale: Bool {
        dataStalenesSeconds > 3600
    }

    static let placeholder = ActivityGoal(
        currency: .activeCalories,
        recommendedTarget: 300,
        agreedTarget: 300,
        hardCap: 1000
    )
}
