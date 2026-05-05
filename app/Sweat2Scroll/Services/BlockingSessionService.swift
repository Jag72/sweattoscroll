// Services/BlockingSessionService.swift
// Solo "earn-your-scroll" friction state machine.
//
// Apple's native Screen Time blocks an app outright. Sweat2Scroll layers a
// behavioral contract on top:
//
//   1. Each day starts with a 30-minute "free window" where locked apps stay
//      open (analogous to iOS Screen Time's allowance).
//   2. After the free window, apps stay blocked until the calorie goal is hit.
//      The shield surfaces the remaining kcal owed.
//   3. The user can buy a 15-minute bypass by writing a justification note
//      ("why am I procrastinating?"). The note is persisted in the App Group.
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
    /// First 30 min of the day — apps usable, but timer is ticking.
    case grace
    /// Grace expired AND goal not yet met — OS shield engaged.
    case blocked
    /// User paid the friction tax and bought 15 min — apps usable.
    case bypass15
    /// User confirmed the day-off after re-reading their justification.
    case dayBypass
}

@MainActor
final class BlockingSessionService: ObservableObject {

    static let shared = BlockingSessionService()

    // MARK: - Published State (observed by SwiftUI)
    @Published private(set) var phase: BlockingPhase = .idle
    @Published private(set) var graceSecondsRemaining: TimeInterval = 0
    @Published private(set) var bypass15SecondsRemaining: TimeInterval = 0
    @Published private(set) var dayBypassEndsAt: Date?
    @Published private(set) var procrastinationNote: String = ""
    @Published private(set) var procrastinationNoteAt: Date?
    @Published private(set) var hasPendingJustificationRequest: Bool = false

    // MARK: - Tunables
    let graceDuration: TimeInterval  = 30 * 60   // 30 min
    let bypassDuration: TimeInterval = 15 * 60   // 15 min

    // MARK: - Persistence
    // Lives in the App Group so the Shield extension reads the same source of
    // truth.
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
    ///
    /// - Parameters:
    ///   - goalReached: true when today's calorie/step goal has been hit.
    ///   - hasSelection: true when the user has at least one app/category/web
    ///                   domain selected to lock.
    func tick(goalReached: Bool, hasSelection: Bool) {
        rolloverIfNewDay()

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
        } else if let end = graceEndsAt, now < end {
            resolved = .grace
            graceSecondsRemaining = max(0, end.timeIntervalSince(now))
        } else {
            resolved = .blocked
        }

        if resolved != .grace {
            graceSecondsRemaining = 0
        }
        if resolved != .bypass15 {
            bypass15SecondsRemaining = 0
        }

        if phase != resolved {
            phase = resolved
            persistPhase(resolved)
        }
    }

    /// Convenience tick that infers grace expiry without changing goal status.
    /// Useful from a periodic timer where we just want the seconds to count
    /// down.
    func passiveTick() {
        let now = Date()
        if let end = graceEndsAt, now < end {
            graceSecondsRemaining = max(0, end.timeIntervalSince(now))
        } else if graceSecondsRemaining > 0 {
            graceSecondsRemaining = 0
        }
        if let end = bypass15EndsAt, now < end {
            bypass15SecondsRemaining = max(0, end.timeIntervalSince(now))
        } else if bypass15SecondsRemaining > 0 {
            bypass15SecondsRemaining = 0
        }
    }

    /// User wrote a justification note and is buying a 15-minute scroll
    /// window. Returns true on success.
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

    /// Partner-issued emergency override. Treats the granted minutes like a
    /// 15-minute window without requiring a justification note. The OS shield
    /// extension's `Sweat2ScrollShieldConfiguration` reads the same App Group
    /// keys so the system shield surface stays in sync.
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

    /// User confirmed they want the day off. We assume they have already been
    /// shown their earlier justification note in `DayUnlockReflectionSheet`.
    func requestDayBypass() {
        let cal = Calendar.current
        // Lasts until next midnight so the user gets a fresh slate tomorrow.
        let endOfDay = cal.startOfDay(for: Date()).addingTimeInterval(24 * 60 * 60)
        defaults.set(endOfDay, forKey: AppGroupKey.blockingDayBypassEndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingBypass15EndsAt)
        defaults.set(false, forKey: AppGroupKey.blockingPendingJustify)
        dayBypassEndsAt = endOfDay
        bypass15SecondsRemaining = 0
        hasPendingJustificationRequest = false
    }

    /// The OS shield extension flips this flag when the user taps "Use 15
    /// minutes" on the system shield. The main app reads it on
    /// `scenePhase == .active` and surfaces the justification sheet.
    func markPendingJustification() {
        defaults.set(true, forKey: AppGroupKey.blockingPendingJustify)
        hasPendingJustificationRequest = true
    }

    /// Called from `RootView.onChange(scenePhase)` to surface pending requests.
    func consumePendingJustification() -> Bool {
        let pending = defaults.bool(forKey: AppGroupKey.blockingPendingJustify)
        if pending {
            defaults.set(false, forKey: AppGroupKey.blockingPendingJustify)
        }
        hasPendingJustificationRequest = false
        return pending
    }

    /// Manual reset (debug / unit tests).
    func resetForToday() {
        defaults.removeObject(forKey: AppGroupKey.blockingDayKey)
        defaults.removeObject(forKey: AppGroupKey.blockingGraceEndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingBypass15EndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingDayBypassEndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingNote)
        defaults.removeObject(forKey: AppGroupKey.blockingNoteAt)
        defaults.removeObject(forKey: AppGroupKey.blockingPendingJustify)
        loadPersisted()
        rolloverIfNewDay()
    }

    // MARK: - Computed Helpers

    var graceMinutesRemaining: Int { Int(ceil(graceSecondsRemaining / 60)) }
    var bypass15MinutesRemaining: Int { Int(ceil(bypass15SecondsRemaining / 60)) }

    /// True when the OS-level Family Controls shield should be engaged.
    var shouldEngageOSShield: Bool { phase == .blocked }

    /// True when the user can use locked apps right now.
    var appsAreOpen: Bool {
        switch phase {
        case .grace, .bypass15, .dayBypass, .unlocked, .idle: return true
        case .blocked: return false
        }
    }

    // MARK: - Internals

    private var graceEndsAt: Date? {
        defaults.object(forKey: AppGroupKey.blockingGraceEndsAt) as? Date
    }
    private var bypass15EndsAt: Date? {
        defaults.object(forKey: AppGroupKey.blockingBypass15EndsAt) as? Date
    }

    private func loadPersisted() {
        procrastinationNote = defaults.string(forKey: AppGroupKey.blockingNote) ?? ""
        procrastinationNoteAt = defaults.object(forKey: AppGroupKey.blockingNoteAt) as? Date
        dayBypassEndsAt = defaults.object(forKey: AppGroupKey.blockingDayBypassEndsAt) as? Date
        hasPendingJustificationRequest = defaults.bool(forKey: AppGroupKey.blockingPendingJustify)

        if let end = graceEndsAt, Date() < end {
            graceSecondsRemaining = end.timeIntervalSinceNow
        }
        if let end = bypass15EndsAt, Date() < end {
            bypass15SecondsRemaining = end.timeIntervalSinceNow
        }
        if let raw = defaults.string(forKey: AppGroupKey.blockingPhase),
           let restored = BlockingPhase(rawValue: raw) {
            phase = restored
        }
    }

    private func persistPhase(_ p: BlockingPhase) {
        defaults.set(p.rawValue, forKey: AppGroupKey.blockingPhase)
    }

    /// Stamps a new daily session if today differs from the persisted day key.
    /// Opens a fresh 30-min grace window and clears yesterday's note + bypasses.
    private func rolloverIfNewDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let todayKey = formatter.string(from: today)

        let lastKey = defaults.string(forKey: AppGroupKey.blockingDayKey)
        guard lastKey != todayKey else { return }

        defaults.set(todayKey, forKey: AppGroupKey.blockingDayKey)
        // Grace runs from "first wake-up moment of the day" rather than midnight
        // so a user who opens the app at 7am still gets 30 useful minutes.
        let graceEnds = Date().addingTimeInterval(graceDuration)
        defaults.set(graceEnds, forKey: AppGroupKey.blockingGraceEndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingBypass15EndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingDayBypassEndsAt)
        defaults.removeObject(forKey: AppGroupKey.blockingNote)
        defaults.removeObject(forKey: AppGroupKey.blockingNoteAt)
        defaults.removeObject(forKey: AppGroupKey.blockingPendingJustify)

        procrastinationNote = ""
        procrastinationNoteAt = nil
        dayBypassEndsAt = nil
        bypass15SecondsRemaining = 0
        hasPendingJustificationRequest = false
        graceSecondsRemaining = graceDuration
    }

    /// Drives the per-second countdown UI even when `evaluatePolicy()` is
    /// running on its 30-second cadence. Cheap — just reads timestamps.
    private func startTicking() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                await self?.passiveTick()
            }
        }
    }
}
