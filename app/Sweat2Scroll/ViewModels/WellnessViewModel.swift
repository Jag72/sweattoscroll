// ViewModels/WellnessViewModel.swift
// WHOOP-style wellness scoring: Recovery, Strain, Sleep, HRV.
// Stores daily scores, 7-day history, workout sessions, and social feed.
// Algorithms from: "Fitness-Contingent Screen Access Control Using OPA and WASM"
// Currently uses HealthKit-derived approximations + mock samples.
// Wire activityVM → fetchHRVMetrics() for live HRV/sleep data.

import Foundation
import SwiftUI

// MARK: - Chart Data Point
struct DayScore: Identifiable {
    let id = UUID()
    let day: String
    let value: Double
}

// MARK: - Heart Rate Sample (for workout chart)
struct HRPoint: Identifiable {
    let id = UUID()
    let minute: Double
    let bpm: Double
}

// MARK: - Workout Session
struct WorkoutSession: Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let duration: Int       // minutes
    let calories: Double
    let strain: Double      // 0–21 scale
    let avgHR: Double       // bpm
    let heartRates: [HRPoint]
    let startedAt: Date

    static let sampleData: [WorkoutSession] = [
        WorkoutSession(
            id: UUID(),
            name: "Morning Run",
            icon: "figure.run",
            duration: 42,
            calories: 380,
            strain: 12.4,
            avgHR: 158,
            heartRates: stride(from: 0.0, to: 42.0, by: 2.0).map { m in
                let wave = sin(m / 6.0) * 18.0 + sin(m / 3.0) * 9.0
                return HRPoint(minute: m, bpm: 148 + wave)
            },
            startedAt: Calendar.current.date(byAdding: .hour, value: -5, to: Date()) ?? Date()
        ),
        WorkoutSession(
            id: UUID(),
            name: "Strength Training",
            icon: "dumbbell.fill",
            duration: 55,
            calories: 295,
            strain: 10.1,
            avgHR: 143,
            heartRates: stride(from: 0.0, to: 55.0, by: 2.0).map { m in
                let wave = sin(m / 8.0) * 25.0 + cos(m / 4.0) * 8.0
                return HRPoint(minute: m, bpm: 138 + wave)
            },
            startedAt: Calendar.current.date(byAdding: .hour, value: -2, to: Date()) ?? Date()
        )
    ]
}

// MARK: - Activity Feed Item
struct ActivityFeedItem: Identifiable {
    let id: UUID
    let partnerName: String
    let partnerInitial: String
    let action: String
    let value: String
    let timestamp: Date
    var applauds: Int
    var hasApplauded: Bool
    let systemIcon: String
    let iconColor: Color

    static let sampleData: [ActivityFeedItem] = [
        ActivityFeedItem(
            id: UUID(),
            partnerName: "Alex",
            partnerInitial: "A",
            action: "hit their calorie goal",
            value: "320 kcal 🔥",
            timestamp: Calendar.current.date(byAdding: .minute, value: -12, to: Date()) ?? Date(),
            applauds: 3,
            hasApplauded: false,
            systemIcon: "flame.fill",
            iconColor: Color(hex: "#FF6B35")
        ),
        ActivityFeedItem(
            id: UUID(),
            partnerName: "Alex",
            partnerInitial: "A",
            action: "completed a workout",
            value: "Morning Run · 42 min",
            timestamp: Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date(),
            applauds: 1,
            hasApplauded: true,
            systemIcon: "figure.run",
            iconColor: Color.electricOrange
        ),
        ActivityFeedItem(
            id: UUID(),
            partnerName: "Alex",
            partnerInitial: "A",
            action: "recovery score",
            value: "Recovery: 81 — Green 💚",
            timestamp: Calendar.current.date(byAdding: .hour, value: -6, to: Date()) ?? Date(),
            applauds: 5,
            hasApplauded: false,
            systemIcon: "bolt.heart.fill",
            iconColor: Color.emeraldGreen
        ),
        ActivityFeedItem(
            id: UUID(),
            partnerName: "Alex",
            partnerInitial: "A",
            action: "logged sleep",
            value: "7h 22m · 91% efficiency",
            timestamp: Calendar.current.date(byAdding: .hour, value: -8, to: Date()) ?? Date(),
            applauds: 2,
            hasApplauded: false,
            systemIcon: "moon.fill",
            iconColor: Color(hex: "#4ECDC4")
        )
    ]
}

// MARK: - Challenge Card
struct ChallengeItem: Identifiable {
    let id: UUID
    let title: String
    let description: String
    let progress: Double
    let target: Double
    let emoji: String
    let color: Color

    var progressFraction: Double { min(progress / max(target, 1), 1.0) }
    var isCompleted: Bool { progress >= target }

    static let sampleData: [ChallengeItem] = [
        ChallengeItem(id: UUID(), title: "Week Warrior", description: "Hit goal 5 days this week",
                       progress: 3, target: 5, emoji: "⚡", color: Color.electricOrange),
        ChallengeItem(id: UUID(), title: "Streak King",  description: "7-day goal streak",
                       progress: 4, target: 7, emoji: "🔥", color: Color(hex: "#FF4D00")),
        ChallengeItem(id: UUID(), title: "Recovery Master", description: "3 Green days in a row",
                       progress: 2, target: 3, emoji: "💚", color: Color.emeraldGreen),
        ChallengeItem(id: UUID(), title: "Heart Champion", description: "HRV > 55ms for 5 days",
                       progress: 3, target: 5, emoji: "❤️‍🔥", color: Color(hex: "#FF6B6B"))
    ]
}

// MARK: - WellnessViewModel
@MainActor
class WellnessViewModel: ObservableObject {

    // MARK: - Today's Scores
    @Published var recoveryScore: Double = 73   // 0–100 (legacy WHOOP-style)
    @Published var strainScore: Double   = 14.2 // 0–21
    @Published var sleepScore: Double    = 82   // 0–100
    @Published var hrv: Double           = 58   // ms RMSSD
    @Published var rhr: Double           = 52   // bpm
    @Published var respiratoryRate: Double = 15.2 // breaths/min

    // MARK: - Energy Score (Apple Activity rings)
    /// Apple-style daily energy: Move + Exercise + Stand averaged into 0–100.
    @Published var energyScore: Double = 0
    @Published var moveProgress: Double = 0     // 0–1 of move goal
    @Published var exerciseProgress: Double = 0 // 0–1 of 30-min exercise goal
    @Published var standProgress: Double = 0    // 0–1 of 12-stand-hour goal
    @Published var exerciseMinutesToday: Double = 0
    @Published var standHoursToday: Double = 0
    @Published var energyHistory: [DayScore] = []

    // MARK: - Trends (per-day chart data — populated from HealthKit)
    @Published var caloriesHistory: [DayScore] = []
    @Published var stepsDailyHistory: [DayScore] = []
    @Published var caloriesToday: Double = 0
    @Published var stepsToday: Int = 0

    // MARK: - Aggregate stats
    var weekStepsTotal: Int { stepsDailyHistory.reduce(0) { $0 + Int($1.value) } }
    var weekStepsAvg: Int   { stepsDailyHistory.isEmpty ? 0 : weekStepsTotal / stepsDailyHistory.count }
    var weekStepsBest: Int  { Int(stepsDailyHistory.map(\.value).max() ?? 0) }
    var weekCaloriesAvg: Int { caloriesHistory.isEmpty ? 0 : Int(caloriesHistory.map(\.value).reduce(0,+)) / caloriesHistory.count }
    var weekRHRAvg: Int { rhrAvg(rhrHistory.map(\.value)) }
    var weekRHRMin: Int { Int(rhrHistory.map(\.value).filter { $0 > 0 }.min() ?? 0) }
    var weekRHRMax: Int { Int(rhrHistory.map(\.value).max() ?? 0) }
    private func rhrAvg(_ values: [Double]) -> Int {
        let nonZero = values.filter { $0 > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return Int(nonZero.reduce(0, +) / Double(nonZero.count))
    }

    /// lnRMSSD — derived metric used in recovery formula
    var lnRMSSD: Double { hrv > 0 ? log(hrv) : 0 }

    // MARK: - Recovery Components (0.0–1.0, normalized)
    // From composite: 0.40·zHRV − 0.25·zRHR − 0.10·zResp + 0.25·Sleep/100 − 0.10·zStrain
    @Published var recoveryHRVComponent:    Double = 0.78
    @Published var recoveryRHRComponent:    Double = 0.65
    @Published var recoveryRespComponent:   Double = 0.71
    @Published var recoverySleepComponent:  Double = 0.82
    @Published var recoveryStrainComponent: Double = 0.72

    // MARK: - Sleep Breakdown (minutes)
    @Published var sleepDeep:       Double = 95
    @Published var sleepREM:        Double = 108
    @Published var sleepLight:      Double = 185
    @Published var sleepAwake:      Double = 22
    @Published var sleepDuration:   Double = 410   // total minutes in bed
    @Published var sleepEfficiency: Double = 0.91  // 0–1

    // Sleep score components (0–1)
    @Published var sleepPerformance:  Double = 0.88
    @Published var sleepConsistency:  Double = 0.74
    @Published var sleepStageQuality: Double = 0.81
    @Published var sleepRespStability: Double = 0.93

    // MARK: - Workouts & Feed
    @Published var workouts:      [WorkoutSession]  = WorkoutSession.sampleData
    @Published var activityFeed:  [ActivityFeedItem] = ActivityFeedItem.sampleData
    @Published var challenges:    [ChallengeItem]   = ChallengeItem.sampleData

    // MARK: - 7-Day History
    @Published var recoveryHistory: [DayScore] = [
        DayScore(day: "Mon", value: 64), DayScore(day: "Tue", value: 71),
        DayScore(day: "Wed", value: 55), DayScore(day: "Thu", value: 80),
        DayScore(day: "Fri", value: 68), DayScore(day: "Sat", value: 77),
        DayScore(day: "Sun", value: 73)
    ]
    @Published var strainHistory: [DayScore] = [
        DayScore(day: "Mon", value: 10.2), DayScore(day: "Tue", value: 13.5),
        DayScore(day: "Wed", value: 7.8),  DayScore(day: "Thu", value: 15.1),
        DayScore(day: "Fri", value: 12.3), DayScore(day: "Sat", value: 16.4),
        DayScore(day: "Sun", value: 14.2)
    ]
    @Published var sleepHistory: [DayScore] = [
        DayScore(day: "Mon", value: 75), DayScore(day: "Tue", value: 88),
        DayScore(day: "Wed", value: 62), DayScore(day: "Thu", value: 91),
        DayScore(day: "Fri", value: 78), DayScore(day: "Sat", value: 84),
        DayScore(day: "Sun", value: 82)
    ]
    @Published var hrvHistory: [DayScore] = [
        DayScore(day: "Mon", value: 52), DayScore(day: "Tue", value: 58),
        DayScore(day: "Wed", value: 47), DayScore(day: "Thu", value: 63),
        DayScore(day: "Fri", value: 55), DayScore(day: "Sat", value: 61),
        DayScore(day: "Sun", value: 58)
    ]
    @Published var rhrHistory: [DayScore] = [
        DayScore(day: "Mon", value: 54), DayScore(day: "Tue", value: 53),
        DayScore(day: "Wed", value: 56), DayScore(day: "Thu", value: 51),
        DayScore(day: "Fri", value: 52), DayScore(day: "Sat", value: 50),
        DayScore(day: "Sun", value: 52)
    ]
    @Published var respHistory: [DayScore] = [
        DayScore(day: "Mon", value: 15.8), DayScore(day: "Tue", value: 15.1),
        DayScore(day: "Wed", value: 16.2), DayScore(day: "Thu", value: 14.9),
        DayScore(day: "Fri", value: 15.5), DayScore(day: "Sat", value: 14.7),
        DayScore(day: "Sun", value: 15.2)
    ]

    // MARK: - Computed Colors
    var recoveryColor: Color {
        if recoveryScore >= 67 { return Color.electricOrange }
        else if recoveryScore >= 34 { return Color(hex: "#FFB700") }
        else { return Color(hex: "#FF4D00") }
    }

    var recoveryLabel: String {
        if recoveryScore >= 67 { return "Green — Ready" }
        else if recoveryScore >= 34 { return "Yellow — Moderate" }
        else { return "Red — Rest" }
    }

    var strainColor: Color {
        if strainScore >= 18      { return Color(hex: "#FF4D00") }
        else if strainScore >= 14 { return Color(hex: "#FF8C00") }
        else if strainScore >= 10 { return Color(hex: "#FFB700") }
        else                      { return Color(hex: "#4ECDC4") }
    }

    var strainLabel: String {
        if strainScore >= 18      { return "All Out" }
        else if strainScore >= 14 { return "Overreaching" }
        else if strainScore >= 10 { return "Strenuous" }
        else                      { return "Moderate" }
    }

    var totalSleepMinutes: Double { sleepDeep + sleepREM + sleepLight }
    var sleepHoursText: String {
        let h = Int(totalSleepMinutes / 60)
        let m = Int(totalSleepMinutes.truncatingRemainder(dividingBy: 60))
        return "\(h)h \(m)m"
    }

    // MARK: - Live HealthKit Data Loader
    // Call this from any dashboard's `.task { }` on appear.
    /// Pulls today + 7-day wellness history from HealthKit and merges into the
    /// published properties. Falls back to the existing sample data only if
    /// HealthKit returns no values (e.g. simulator or unauthorized).
    func loadLiveData() async {
        await loadLiveData(from: HealthKitService.shared)
    }

    func loadLiveData(from healthKit: HealthKitService) async {
        await loadLiveData(from: healthKit, moveGoalKcal: 500)
    }

    /// Same as `loadLiveData(from:)` but takes the user's actual Move goal so
    /// the Energy score scales correctly to their target.
    func loadLiveData(from healthKit: HealthKitService, moveGoalKcal: Double) async {
        if !healthKit.isAuthorized {
            try? await healthKit.requestAuthorization()
        }

        // Trigger the fetch (no-op if HealthKit is unavailable or not authorized)
        try? await healthKit.fetchTodayMetrics()
        await healthKit.fetchWellnessMetrics()
        await healthKit.fetchWeeklyHistory()

        // ───── Apple Activity ring → Energy score ───────────────────────────
        let safeMoveGoal = max(moveGoalKcal, 100) // avoid /0; fall back to 100
        let move     = min(healthKit.activeCaloriesToday  / safeMoveGoal, 1.0)
        let exercise = min(healthKit.exerciseMinutesToday / 30.0, 1.0)
        let stand    = min(healthKit.standHoursToday      / 12.0, 1.0)
        moveProgress     = move
        exerciseProgress = exercise
        standProgress    = stand
        exerciseMinutesToday = healthKit.exerciseMinutesToday
        standHoursToday      = healthKit.standHoursToday
        energyScore = ((move + exercise + stand) / 3.0) * 100

        // 7-day energy history
        let labels = Self.weekLabels()
        var energyDays: [DayScore] = []
        for i in 0..<7 {
            let cal = i < healthKit.calorieHistory.count  ? healthKit.calorieHistory[i]  : 0
            let ex  = i < healthKit.exerciseHistory.count ? healthKit.exerciseHistory[i] : 0
            let st  = i < healthKit.standHistory.count    ? healthKit.standHistory[i]    : 0
            let mv  = min(cal / safeMoveGoal, 1.0)
            let exR = min(ex  / 30.0, 1.0)
            let stR = min(st  / 12.0, 1.0)
            energyDays.append(DayScore(day: labels[i], value: ((mv + exR + stR) / 3.0) * 100))
        }
        energyHistory = energyDays

        // 7-day calorie + step history for the trends page
        caloriesHistory = zip(labels, healthKit.calorieHistory).map { DayScore(day: $0.0, value: $0.1) }
        stepsDailyHistory = zip(labels, healthKit.stepsHistory).map { DayScore(day: $0.0, value: $0.1) }
        caloriesToday = healthKit.activeCaloriesToday
        stepsToday = healthKit.stepsToday

        // HRV — only update if we received a real value (0 means no sample today)
        if healthKit.hrvSDNN > 0 {
            hrv = healthKit.hrvSDNN
        }

        // Resting Heart Rate
        if healthKit.restingHeartRate > 0 {
            rhr = healthKit.restingHeartRate
        }

        // Respiratory Rate
        if healthKit.respiratoryRate > 0 {
            respiratoryRate = healthKit.respiratoryRate
        }

        // Sleep — update sleep duration and re-derive sleep score components
        if healthKit.sleepMinutesLast > 0 {
            let totalMinutes = healthKit.sleepMinutesLast
            sleepDuration = totalMinutes

            // Rough stage distribution based on typical proportions when live data
            // does not include per-stage breakdown (Apple Watch provides full stages).
            let effectiveMinutes = min(totalMinutes, 480)  // cap at 8 h for scoring
            sleepDeep   = effectiveMinutes * 0.23  // ~23% deep is ideal
            sleepREM    = effectiveMinutes * 0.26  // ~26% REM is ideal
            sleepLight  = effectiveMinutes * 0.51
            sleepAwake  = max(0, totalMinutes - effectiveMinutes)
            sleepEfficiency = totalMinutes > 0 ? min(effectiveMinutes / totalMinutes, 1.0) : 0

            // Recalculate sleep score (0–100) from duration + efficiency
            let durationScore   = min(totalMinutes / 480.0, 1.0)  // 8 h = 100%
            let efficiencyScore = sleepEfficiency
            sleepScore = ((durationScore * 0.6) + (efficiencyScore * 0.4)) * 100
        }

        // Recompute recovery score from updated HRV, RHR, respiratory rate, sleep
        // Formula from paper: 0.40·lnRMSSD − 0.25·RHR_norm − 0.10·Resp_norm + 0.25·Sleep/100
        // Values are normalized against typical ranges; clamped to 0–100.
        let hrvNorm  = min(hrv / 100.0, 1.0)    // 0–100 ms range
        let rhrNorm  = max(0, 1.0 - (rhr - 40.0) / 60.0)  // 40–100 bpm → 1.0–0.0
        let respNorm = max(0, 1.0 - (respiratoryRate - 12.0) / 12.0)  // 12–24 → 1.0–0.0
        let sleepNorm = sleepScore / 100.0

        // Update recovery components for the UI breakdown bars
        recoveryHRVComponent    = hrvNorm
        recoveryRHRComponent    = rhrNorm
        recoveryRespComponent   = respNorm
        recoverySleepComponent  = sleepNorm

        let rawRecovery = (0.40 * hrvNorm + 0.25 * rhrNorm + 0.10 * respNorm + 0.25 * sleepNorm)
        recoveryScore = min(max(rawRecovery * 100, 0), 100)

        // Merge 7-day history into chart arrays. Index 0 = 6 days ago, 6 = today.
        let nonZero = { (arr: [Double]) -> Bool in arr.contains(where: { $0 > 0 }) }

        if nonZero(healthKit.hrvHistory) {
            hrvHistory = zip(labels, healthKit.hrvHistory).map { DayScore(day: $0.0, value: $0.1) }
        }
        if nonZero(healthKit.rhrHistory) {
            rhrHistory = zip(labels, healthKit.rhrHistory).map { DayScore(day: $0.0, value: $0.1) }
        }
        if nonZero(healthKit.respHistory) {
            respHistory = zip(labels, healthKit.respHistory).map { DayScore(day: $0.0, value: $0.1) }
        }

        // Sleep-score per-day history derived from per-day sleep minutes (0–100).
        if nonZero(healthKit.sleepHistory) {
            sleepHistory = zip(labels, healthKit.sleepHistory).map { (day, minutes) in
                let score = min(minutes / 480.0, 1.0) * 100
                return DayScore(day: day, value: score)
            }
        }

        // Recovery history: composite per day using HRV, RHR, sleep when all available.
        if nonZero(healthKit.hrvHistory) || nonZero(healthKit.sleepHistory) {
            recoveryHistory = (0..<min(7, healthKit.hrvHistory.count)).map { i in
                let hrvD  = i < healthKit.hrvHistory.count ? healthKit.hrvHistory[i] : 0
                let rhrD  = i < healthKit.rhrHistory.count ? healthKit.rhrHistory[i] : 0
                let respD = i < healthKit.respHistory.count ? healthKit.respHistory[i] : 0
                let slpD  = i < healthKit.sleepHistory.count ? healthKit.sleepHistory[i] : 0

                let h = min(hrvD / 100.0, 1.0)
                let r = max(0, 1.0 - (rhrD - 40.0) / 60.0)
                let p = max(0, 1.0 - (respD - 12.0) / 12.0)
                let s = min(slpD / 480.0, 1.0)
                let composite = (0.40 * h + 0.25 * r + 0.10 * p + 0.25 * s) * 100
                return DayScore(day: labels[i], value: min(max(composite, 0), 100))
            }
        }

        // Strain history derived from active-calorie history (rough proxy: 0–21 scale).
        if nonZero(healthKit.calorieHistory) {
            strainHistory = zip(labels, healthKit.calorieHistory).map { (day, kcal) in
                // 0 kcal → 0 strain, 800 kcal → ~21 (matches WHOOP-ish scale)
                DayScore(day: day, value: min(kcal / 800.0 * 21.0, 21.0))
            }
            strainScore = strainHistory.last?.value ?? strainScore
        }
    }

    /// Returns 7 labels Mon..Sun in the order matching `loadLiveData`'s
    /// chronological history (oldest → today).
    private static func weekLabels() -> [String] {
        let symbols = ["M", "T", "W", "T", "F", "S", "S"]
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date()) // 1=Sun…7=Sat
        // Convert to Monday-based index 0…6 where Sunday = 6
        let mondayIdx = (weekday + 5) % 7
        // We want oldest day first, today last
        var ordered: [String] = []
        for offset in (0...6).reversed() {
            let idx = (mondayIdx - offset + 7) % 7
            ordered.append(symbols[idx])
        }
        return ordered
    }

    // MARK: - Applaud Action
    func toggleApplaud(for itemID: UUID) {
        guard let idx = activityFeed.firstIndex(where: { $0.id == itemID }) else { return }
        if activityFeed[idx].hasApplauded {
            activityFeed[idx].applauds -= 1
            activityFeed[idx].hasApplauded = false
        } else {
            activityFeed[idx].applauds += 1
            activityFeed[idx].hasApplauded = true
        }
        HapticEngine.impact(.light)
    }
}
