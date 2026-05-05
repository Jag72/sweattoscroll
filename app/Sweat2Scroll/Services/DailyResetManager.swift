// DailyResetManager.swift
// PRD §5A — midnight reset, 30‑min free window, shield re-apply.

import Foundation
import Combine

@MainActor
final class DailyResetManager: ObservableObject {
    static let shared = DailyResetManager()

    static let dailyCaloriesBurnedKey = "dailyCaloriesBurned"
    static let freeWindowEndKey       = "freeWindowEnd"
    static let dailyCalorieGoalKey    = "dailyCalorieGoal"
    private  let lastResetDateKey     = "dailyResetLastDate"

    /// Non-nil while the 30-min free window is active (midnight → +30 min).
    @Published private(set) var freeWindowEnd: Date?

    /// True when the current time is inside today's free window.
    var isFreeWindowActive: Bool {
        guard let end = freeWindowEnd else { return false }
        return Date() < end
    }

    /// Remaining seconds in the free window (0 when not active).
    var freeWindowRemainingSeconds: TimeInterval {
        guard let end = freeWindowEnd, Date() < end else { return 0 }
        return end.timeIntervalSinceNow
    }

    private init() {
        freeWindowEnd = UserDefaults.standard.object(forKey: Self.freeWindowEndKey) as? Date
        performMidnightResetIfNeeded()
    }

    // MARK: - Midnight reset

    /// Call from `scenePhase == .active` and from a BGAppRefreshTask.
    func performMidnightResetIfNeeded() {
        let calendar  = Calendar.current
        let today     = calendar.startOfDay(for: Date())
        let lastReset = (UserDefaults.standard.object(forKey: lastResetDateKey) as? Date)
                        .map { calendar.startOfDay(for: $0) }
                        ?? Date.distantPast

        guard today > lastReset else { return }

        // Reset burned calories for the new day.
        UserDefaults.standard.set(0.0, forKey: Self.dailyCaloriesBurnedKey)

        // Open the 30-minute free window starting at midnight.
        let windowEnd = today.addingTimeInterval(30 * 60)
        freeWindowEnd = windowEnd
        UserDefaults.standard.set(windowEnd, forKey: Self.freeWindowEndKey)

        // Persist today as the last reset date.
        UserDefaults.standard.set(today, forKey: lastResetDateKey)
    }

    // MARK: - Extension (+15 min)

    /// Extends the free window (or creates a new one) by 15 minutes from now.
    /// Returns the new expiry date.
    @discardableResult
    func grantExtension(minutes: Int = 15) -> Date {
        let base   = max(freeWindowEnd ?? Date(), Date())
        let newEnd = base.addingTimeInterval(TimeInterval(minutes * 60))
        freeWindowEnd = newEnd
        UserDefaults.standard.set(newEnd, forKey: Self.freeWindowEndKey)
        return newEnd
    }

    // MARK: - Manual calorie update (HealthKit bridge)

    func updateDailyCaloriesBurned(_ kcal: Double) {
        UserDefaults.standard.set(kcal, forKey: Self.dailyCaloriesBurnedKey)
    }

    var dailyCaloriesBurned: Double {
        UserDefaults.standard.double(forKey: Self.dailyCaloriesBurnedKey)
    }

    var dailyCalorieGoal: Double {
        UserDefaults.standard.double(forKey: Self.dailyCalorieGoalKey)
    }

    var goalReached: Bool {
        dailyCalorieGoal > 0 && dailyCaloriesBurned >= dailyCalorieGoal
    }
}
