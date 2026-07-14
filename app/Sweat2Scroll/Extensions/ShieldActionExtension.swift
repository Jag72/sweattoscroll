// Extensions/ShieldActionExtension.swift
// ⚠️  This file lives in the MAIN APP target and contains ONLY the shared
//     enums/constants needed by main-app code (e.g. ScreenTimeService).
//
// The actual ShieldActionDelegate subclass lives exclusively in:
//   ShieldActionExtension/Sweat2ScrollShieldAction.swift
// It must NOT be compiled into the main app target — doing so causes
// "duplicate symbol" linker errors and override-conflict compile errors.

import Foundation

// MARK: - Bypass Options (mirrors native iOS Screen Time)
// Shared between the main app UI and the extension's button handler.
enum BypassOption: String, CaseIterable {
    case oneMinute   = "1 Minute"
    case fifteenMin  = "15 Minutes"
    case ignoreToday = "Ignore for Today"    // Requires Break-Glass TOTP
    case syncData    = "Sync My Workout Data" // Triggers Timer Fallback
}

// MARK: - App Group Keys (shared constants)
// Using a namespace enum avoids string-literal duplication across targets.
enum AppGroupKey {
    static let syncTimerRequested     = "syncTimerRequested"
    static let selfRegBypassRequested = "selfRegBypassRequested"
    static let selfRegBypassAt        = "selfRegBypassRequestedAt"
    static let currentCalories        = "currentCalories"
    static let currentGoal            = "currentGoal"
    static let goalCurrency           = "goalCurrency"
    static let isGracePeriodActive    = "isGracePeriodActive"
    static let isShieldActive         = "isShieldActive"
    static let activitySelection      = "activitySelection"
    /// Main app's CFBundleIdentifier — persisted because `.appex` targets have a different `Bundle.main`.
    static let hostAppBundleIdentifier = "hostAppBundleIdentifier"

    // MARK: - Solo Blocking-Session State Machine
    // Persists the daily 30-min grace window, 15-min bypass window, day bypass,
    // and the user's "why am I procrastinating?" justification note. The OS
    // shield extension reads these to render contextual messaging; the main app
    // reads them to drive the in-app block flow.
    static let blockingPhase           = "blockingSession.phase"
    static let blockingDayKey          = "blockingSession.dayKey"
    static let blockingGraceEndsAt     = "blockingSession.graceEndsAt"
    static let blockingBypass15EndsAt  = "blockingSession.bypass15EndsAt"
    static let blockingDayBypassEndsAt = "blockingSession.dayBypassEndsAt"
    static let blockingNote            = "blockingSession.note"
    static let blockingNoteAt          = "blockingSession.noteAt"
    static let blockingPendingJustify  = "blockingSession.pendingJustify"

    // MARK: - Per-app daily usage limits (DeviceActivityEvent thresholds)
    /// Encoded `[Data]` manifest of monitored `ApplicationToken`s (index → event).
    static let usageMonitorAppTokenData      = "usageMonitor.appTokenData"
    static let usageMonitorCatTokenData      = "usageMonitor.catTokenData"
    /// Indices (into the manifest) of apps/categories that hit their daily limit.
    static let exhaustedAppIndices           = "usageMonitor.exhaustedAppIndices"
    static let exhaustedCatIndices           = "usageMonitor.exhaustedCatIndices"
    /// Legacy keys — cleared on rollover; kept for migration.
    static let exhaustedApplicationTokenData = "usageMonitor.exhaustedAppTokenData"
    static let exhaustedCategoryTokenData    = "usageMonitor.exhaustedCatTokenData"
    /// Written by the main app so extensions know whether the calorie goal is met.
    static let goalReached                   = "blockingSession.goalReached"
}
