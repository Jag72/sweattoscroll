// Services/BlockingSessionService.swift
// Solo "earn-your-scroll" friction state machine.
//
// Apple's native Screen Time blocks an app outright. Sweat2Scroll layers a
// behavioral contract on top:
//
//   1. Each selected app gets its own 30-minute daily usage allowance
//      (tracked by DeviceActivity — the timer starts when the user opens
//      that app, NOT when Sweat2Scroll launches).
//   2. After an app hits 30 min, only that app is shielded until the calorie
//      goal is met. Instagram and Facebook are counted separately.
//   3. The user can buy a 15-minute bypass by writing a justification note.
//   4. If the user later wants the day off entirely, we replay their earlier
//      note as a friction-mirror before granting the day-long bypass.
//
// All state lives in the App Group container so the Shield Configuration
// Extension (separate sandboxed process) can render contextual messaging.

import Foundation
import Combine

enum BlockingPhase: String, Codable {
    /// No apps selected to lock — banners stay quiet.
    case idle
    /// Goal hit (or manual day bypass / 15-min bypass) — apps usable.
    case unlocked
    /// Per-app usage monitoring — some apps may be shielded, others still open.
    case monitoring
    /// Every selected app/category hit its 30-min limit AND goal not yet met.
    case blocked
    /// User paid the friction tax and bought 15 min — apps usable.
    case bypass15
    /// User confirmed the day-off after re-reading their justification.
    case dayBypass

    /// Legacy persisted value — map to the new per-app monitoring phase.
    static func migrated(from raw: String) -> BlockingPhase? {
        if raw == "grace" { return .monitoring }
        return BlockingPhase(rawValue: raw)
    }
}

@MainActor
final class BlockingSessionService: ObservableObject {

    static let shared = BlockingSessionService()

    // MARK: - Published State (observed by SwiftUI)
    @Published private(set) var phase: BlockingPhase = .idle
    @Published private(set) var bypass15SecondsRemaining: TimeInterval = 0
    @Published private(set) var dayBypassEndsAt: Date?
    @Published private(set) var procrastinationNote: String = ""
    @Published private(set) var procrastinationNoteAt: Date?
    @Published private(set) var hasPendingJustificationRequest: Bool = false

    /// How many selected apps/categories have hit their 30-min limit today.
    @Published private(set) var exhaustedTargetCount: Int = 0
    /// Total selected apps/categories being monitored.
    @Published private(set) var monitoredTargetCount: Int = 0

    // MARK: - Tunables
    let bypassDuration: TimeInterval = 15 * 60   // 15 min

    // MARK: - Persistence
    private let appGroupID = "group.com.sweat2scroll.appblocker"
    private var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // MARK: - Tick Timer
    private var tickTask: Task<Void, Never>?

    private init() {
        loadPersisted()
        rolloverIfNewDay()
        startTicking()
    }

    deinit {
        tickTask?.cancel()
    }

    // MARK: - Public API

    /// Recompute the active phase. Call from `ActivityViewModel.evaluatePolicy()`
    /// every time the calorie/step goal is re-checked, and on app foreground.
    func tick(goalReached: Bool, hasSelection: Bool) {
        rolloverIfNewDay()

        let selection = ScreenTimeService.shared.activitySelection
        let usage = PerAppUsageMonitorService.shared
        usage.refreshPublishedCounts(selection: selection)
        exhaustedTargetCount = usage.exhaustedAppCount
        monitoredTargetCount = usage.monitoredAppCount

        let resolved: BlockingPhase
        let now = Date()

        if !hasSelection {
            resolved = .idle
        } else if goalReached {
            resolved = .unlocked
        } else if let end = dayBypassEndsAt, now < end {
            resolved = .dayBypass
        } else if let end = bypass15EndsAt, now < end {
            resolved = .bypass15
            bypass15SecondsRemaining = max(0, end.timeIntervalSince(now))
        } else if usage.allTargetsExhausted(for: selection) {
            resolved = .blocked
        } else {
            resolved = .monitoring
        }

        if resolved != .bypass15 {
            bypass15SecondsRemaining = 0
        }

        if phase != resolved {
            phase = resolved
            persistPhase(resolved)
        }
    }

    func passiveTick() {
        let now = Date()
        if let end = bypass15EndsAt, now < end {
            bypass15SecondsRemaining = max(0, end.timeIntervalSince(now))
        } else if bypass15SecondsRemaining > 0 {
            bypass15SecondsRemaining = 0
        }
    }

    @discardableResult
    func requestFifteenMinuteBypass(note: String) -> Bool {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        defaults.set(trimmed, forKey: AppGroupKey.blockingNote)
        defaults.set(Date(), forKey: AppGroupKey.blockingNoteAt)

        let endsAt = Date().addingTimeInterval(bypassDuration)
        defaults.set(endsAt, forKey: AppGroupKey.blockingBypass15EndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingDayBypassEndsAt)
        defaults.set(false, forKey: AppGroupKey.blockingPendingJustify)

        procrastinationNote = trimmed
        procrastinationNoteAt = Date()
        hasPendingJustificationRequest = false
        bypass15SecondsRemaining = bypassDuration
        return true
    }

    func applyPartnerOverride(minutes: Int, fromName: String, reason: String?) {
        let clamped = max(5, min(minutes, 240))
        let endsAt = Date().addingTimeInterval(TimeInterval(clamped) * 60)
        let note = reason?.isEmpty == false
            ? "Partner override (\(fromName)): \(reason!)"
            : "Partner override granted by \(fromName)"
        defaults.set(note, forKey: AppGroupKey.blockingNote)
        defaults.set(Date(), forKey: AppGroupKey.blockingNoteAt)

        defaults.set(endsAt, forKey: AppGroupKey.blockingBypass15EndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingDayBypassEndsAt)
        defaults.set(false, forKey: AppGroupKey.blockingPendingJustify)

        procrastinationNote = note
        procrastinationNoteAt = Date()
        hasPendingJustificationRequest = false
        bypass15SecondsRemaining = TimeInterval(clamped) * 60
    }

    func requestDayBypass() {
        let cal = Calendar.current
        let endOfDay = cal.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60)
        defaults.set(endOfDay, forKey: AppGroupKey.blockingDayBypassEndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingBypass15EndsAt)
        defaults.set(false, forKey: AppGroupKey.blockingPendingJustify)
        dayBypassEndsAt = endOfDay
        bypass15SecondsRemaining = 0
        hasPendingJustificationRequest = false
    }

    func markPendingJustification() {
        defaults.set(true, forKey: AppGroupKey.blockingPendingJustify)
        hasPendingJustificationRequest = true
    }

    func consumePendingJustification() -> Bool {
        let pending = defaults.bool(forKey: AppGroupKey.blockingPendingJustify)
        if pending {
            defaults.set(false, forKey: AppGroupKey.blockingPendingJustify)
        }
        hasPendingJustificationRequest = false
        return pending
    }

    func resetForToday() {
        defaults.removeObject(forKey: AppGroupKey.blockingDayKey)
        defaults.removeObject(forKey: AppGroupKey.blockingBypass15EndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingDayBypassEndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingNote)
        defaults.removeObject(forKey: AppGroupKey.blockingNoteAt)
        defaults.removeObject(forKey: AppGroupKey.blockingPendingJustify)
        PerAppUsageMonitorService.shared.resetDailyExhaustion()
        loadPersisted()
        rolloverIfNewDay()
    }

    // MARK: - Computed Helpers

    var bypass15MinutesRemaining: Int { Int(ceil(bypass15SecondsRemaining / 60)) }

    var shouldEngageOSShield: Bool { phase == .blocked || phase == .monitoring }

    var appsAreOpen: Bool {
        switch phase {
        case .monitoring, .bypass15, .dayBypass, .unlocked, .idle: return true
        case .blocked: return false
        }
    }

    // MARK: - Internals

    private var bypass15EndsAt: Date? {
        defaults.object(forKey: AppGroupKey.blockingBypass15EndsAt) as? Date
    }

    private func loadPersisted() {
        procrastinationNote = defaults.string(forKey: AppGroupKey.blockingNote) ?? ""
        procrastinationNoteAt = defaults.object(forKey: AppGroupKey.blockingNoteAt) as? Date
        dayBypassEndsAt = defaults.object(forKey: AppGroupKey.blockingDayBypassEndsAt) as? Date
        hasPendingJustificationRequest = defaults.bool(forKey: AppGroupKey.blockingPendingJustify)

        if let end = bypass15EndsAt, Date() < end {
            bypass15SecondsRemaining = end.timeIntervalSinceNow
        }
        if let raw = defaults.string(forKey: AppGroupKey.blockingPhase),
           let restored = BlockingPhase.migrated(from: raw) {
            phase = restored
        }
    }

    private func persistPhase(_ p: BlockingPhase) {
        defaults.set(p.rawValue, forKey: AppGroupKey.blockingPhase)
    }

    /// Stamps a new daily session if today differs from the persisted day key.
    /// Clears per-app exhaustion and restarts DeviceActivity monitoring.
    private func rolloverIfNewDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let todayKey = formatter.string(from: today)

        let lastKey = defaults.string(forKey: AppGroupKey.blockingDayKey)
        guard lastKey != todayKey else { return }

        defaults.set(todayKey, forKey: AppGroupKey.blockingDayKey)
        defaults.removeObject(forKey: AppGroupKey.blockingBypass15EndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingDayBypassEndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingNote)
        defaults.removeObject(forKey: AppGroupKey.blockingNoteAt)
        defaults.removeObject(forKey: AppGroupKey.blockingPendingJustify)
        // Legacy key from the old global grace window — clear on rollover.
        defaults.removeObject(forKey: AppGroupKey.blockingGraceEndsAt)

        procrastinationNote = ""
        procrastinationNoteAt = nil
        dayBypassEndsAt = nil
        bypass15SecondsRemaining = 0
        hasPendingJustificationRequest = false

        PerAppUsageMonitorService.shared.resetDailyExhaustion()
        defaults.removeObject(forKey: AppGroupKey.exhaustedApplicationTokenData)
        defaults.removeObject(forKey: AppGroupKey.exhaustedCategoryTokenData)
        PerAppUsageMonitorService.shared.refreshMonitoring(
            for: ScreenTimeService.shared.activitySelection
        )
    }

    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                await self?.passiveTick()
            }
        }
    }
}
