// ViewModels/ActivityViewModel.swift
// Primary coordinator. Bridges HealthKit data → OPA policy evaluation → ScreenTime enforcement.
// Manages the grace period timer, override state, and daily goal progress.

import Foundation
import Combine

@MainActor
class ActivityViewModel: ObservableObject {

    // MARK: - Published State (drives all UI)
    @Published var activityGoal: ActivityGoal = .placeholder
    @Published var isShieldActive: Bool = false
    @Published var isUnlocked: Bool = false
    @Published var overrideState: OverrideState = .inactive
    @Published var isGracePeriodActive: Bool = false
    @Published var gracePeriodRemainingSeconds: Int = 300  // 5 minutes
    @Published var isSyncTimerActive: Bool = false
    @Published var syncTimerRemainingSeconds: Int = 60
    @Published var lastPolicyResult: PolicyResult = .denied
    @Published var isLoading: Bool = false
    /// Today’s step count from HealthKit (updated in `evaluatePolicy`).
    @Published var stepsToday: Int = 0

    // MARK: - Services
    /// Public so views can subscribe / trigger refresh without spawning a duplicate store.
    let healthKit             = HealthKitService.shared
    private let opaService    = OPAService.shared
    private let screenTime    = ScreenTimeService.shared
    private let cloudKit      = CloudKitService.shared
    private let tamperService = TamperDetectionService.shared

    // MARK: - Timers
    private var gracePeriodTimer: Task<Void, Never>?
    private var syncPollingTimer: Task<Void, Never>?
    private var policyEvalTimer: Timer?

    /// Tracks the previous resolved Solo blocking-phase so we only fire shield
    /// engage / disengage on transitions (avoiding double-scheduling of
    /// DeviceActivity bypass windows on every 30-second policy tick).
    private var lastBlockingPhase: BlockingPhase = .idle

    // MARK: - Initialization
    init() {
        Task {
            await initialize()
        }
    }

    // MARK: - Setup
    func initialize() async {
        isLoading = true
        do {
            // 1. Request HealthKit authorization
            try await healthKit.requestAuthorization()

            // 2. Compute calorie goal — prefer the user's saved goal so the
            // dashboard percentage matches what they set in onboarding.
            activityGoal = makeActivityGoal(profile: healthKit.userProfile)

            // 3. Load persisted shield state
            screenTime.loadSelection()
            isShieldActive = screenTime.isShieldActive

            // 4. Load Wasm policy module (cold start ~38ms)
            try opaService.loadModule()

            // 5. Start tamper detection watchdog
            tamperService.startMonitoring()

            // 6. Start continuous policy evaluation loop
            startPolicyEvaluationLoop()

            // 7. Sync to CloudKit
            await cloudKit.subscribeToPartnerUpdates()

        } catch {
            print("[ActivityVM] Initialization error: \(error)")
        }
        isLoading = false
    }

    // MARK: - Continuous Policy Evaluation Loop
    // Re-evaluates the OPA policy every 30 seconds and on HealthKit updates.
    private func startPolicyEvaluationLoop() {
        policyEvalTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.evaluatePolicy() }
        }
        Task { await evaluatePolicy() }
    }

    /// Pulls all health metrics (today + 7-day history) and re-evaluates the policy.
    /// Call from dashboards on appear / `.refreshable`. Also asks for HealthKit
    /// permission whenever we don't yet know we have it — iOS shows the system
    /// sheet only on first call, so this is safe to invoke repeatedly.
    func refreshFromHealthKit() async {
        if healthKit.isHealthKitAvailable && !healthKit.isAuthorized {
            try? await healthKit.requestAuthorization()
        }
        try? await healthKit.fetchTodayMetrics()
        try? await healthKit.fetchUserProfile()
        await healthKit.fetchWellnessMetrics()
        await healthKit.fetchWeeklyHistory()
        // Confirm we actually got data — surfaces the "user denied in Settings"
        // case so dashboards can render the recovery banner.
        await healthKit.verifyAccess()
        await evaluatePolicy()
    }

    /// Call after the user saves height / weight / age (manual onboarding or Profile sheet).
    func refreshActivityGoalFromProfile() {
        activityGoal = makeActivityGoal(profile: healthKit.userProfile)
    }

    /// Builds an `ActivityGoal` honoring the user's onboarding-picked target
    /// (UserDefaults / CloudKit) when available, falling back to the
    /// CDC-derived `CalorieEngine` recommendation. Hard cap is always applied.
    private func makeActivityGoal(profile: UserProfile?) -> ActivityGoal {
        // Engine-derived recommendation gives us hardCap and a sensible default.
        let base: ActivityGoal
        if let p = profile {
            base = CalorieEngine.computeGoal(for: p)
        } else {
            base = .placeholder
        }

        // Prefer the goal the user actually picked. Order:
        //   1. UserDefaults (set right when onboarding finishes — survives cold start).
        //   2. CloudKit-cached account (`dailyTargetKcal`).
        let savedGoal: Double? = {
            let ud = UserDefaults.standard.double(forKey: "dailyCalorieGoal")
            if ud >= 50 { return ud }
            if let acc = AuthManager.shared.cachedAccount,
               let target = acc.dailyTargetKcal, target >= 50 {
                return target
            }
            return nil
        }()

        guard let user = savedGoal else { return base }
        let clamped = min(user, base.hardCap)
        var goal = base
        goal.agreedTarget = clamped
        return goal
    }

    func evaluatePolicy() async {
        // Sync latest HealthKit data
        try? await healthKit.fetchTodayMetrics()

        switch activityGoal.currency {
        case .activeCalories:
            activityGoal.currentProgress = healthKit.activeCaloriesToday
        case .steps:
            activityGoal.currentProgress = Double(healthKit.stepsToday)
        }
        activityGoal.lastSampleTimestamp = healthKit.lastSyncDate
        stepsToday = healthKit.stepsToday

        let calorieGoalForPolicy: Double
        let stepsGoalForPolicy: Int
        switch activityGoal.currency {
        case .activeCalories:
            calorieGoalForPolicy = activityGoal.agreedTarget
            stepsGoalForPolicy = CalorieEngine.stepsEquivalent(
                for: activityGoal.agreedTarget,
                profile: healthKit.userProfile ?? .placeholder
            )
        case .steps:
            calorieGoalForPolicy = activityGoal.recommendedTarget
            stepsGoalForPolicy = Int(activityGoal.agreedTarget.rounded())
        }

        // Build OPA input
        let input = PolicyInput(
            currentActiveCalories: healthKit.activeCaloriesToday,
            currentSteps: healthKit.stepsToday,
            dailyCalorieGoal: calorieGoalForPolicy,
            dailyStepsGoal: stepsGoalForPolicy,
            goalCurrency: activityGoal.currency.rawValue == "Active Calories" ? "activeCalories" : "steps",
            overrideActive: overrideState.isValid,
            overrideExpiration: overrideState.expiresAt.timeIntervalSince1970,
            currentTime: Date().timeIntervalSince1970,
            dataStatenessSeconds: activityGoal.dataStalenesSeconds,
            uiTimerExpired: !isSyncTimerActive && syncTimerRemainingSeconds == 0,
            timeDriftDetected: tamperService.isTimeDriftDetected
        )

        // Evaluate policy — tries Wasm first, falls back to native Swift if unavailable
        let result = opaService.evaluateWithFallback(input: input)
        lastPolicyResult = result

        // Drive the Solo blocking-session state machine: grace → blocked →
        // bypass15 / dayBypass / unlocked. The OS shield is only engaged when
        // the resolved phase is `.blocked`; every other phase lets the user
        // through (with appropriate friction).
        let hasSelection = !screenTime.activitySelection.applicationTokens.isEmpty
                        || !screenTime.activitySelection.categoryTokens.isEmpty
                        || !screenTime.activitySelection.webDomainTokens.isEmpty

        BlockingSessionService.shared.tick(goalReached: result.allow,
                                           hasSelection: hasSelection)
        let phase = BlockingSessionService.shared.phase
        syncShield(forPhase: phase, hasSelection: hasSelection)

        // Mirror today's calorie progress to the App Group so the OS shield
        // extension can render contextual messaging.
        let groupDefaults = UserDefaults(suiteName: "group.com.sweat2scroll.appblocker")
        groupDefaults?.set(healthKit.activeCaloriesToday, forKey: AppGroupKey.currentCalories)
        groupDefaults?.set(activityGoal.agreedTarget, forKey: AppGroupKey.currentGoal)
        groupDefaults?.set(activityGoal.currency.codeName, forKey: AppGroupKey.goalCurrency)

        if !result.allow && result.requiresGracePeriod && !isGracePeriodActive {
            startGracePeriod()
        }

        // Sync progress to CloudKit
        await cloudKit.syncMyProgress(
            calories: healthKit.activeCaloriesToday,
            steps: healthKit.stepsToday,
            goal: activityGoal
        )
    }

    /// Reconciles the OS-level Family Controls shield with the current Solo
    /// blocking-session phase. Only acts on phase transitions so we don't
    /// re-schedule DeviceActivity bypass windows on every 30-second tick.
    private func syncShield(forPhase phase: BlockingPhase, hasSelection: Bool) {
        defer { lastBlockingPhase = phase }
        isUnlocked = (phase != .blocked)

        guard hasSelection else {
            if isShieldActive {
                screenTime.disengageMasterShield()
                isShieldActive = false
            }
            return
        }

        // Skip work when nothing changed.
        if phase == lastBlockingPhase { return }

        switch phase {
        case .blocked:
            screenTime.engageMasterShield()
            isShieldActive = true
            logAuditEvent(type: .shieldEngaged)

        case .grace:
            // Drop the shield + schedule re-engagement when grace expires.
            // The DeviceActivityMonitor extension fires `intervalDidEnd` even
            // if Sweat2Scroll is suspended, so the shield comes back even when
            // the user is sitting in a third-party app.
            let mins = max(1, Int(ceil(BlockingSessionService.shared.graceSecondsRemaining / 60)))
            screenTime.temporaryBypass(minutes: mins)
            isShieldActive = false
            logAuditEvent(type: .shieldDisengaged,
                          notes: "Grace window opened (\(mins) min)")

        case .bypass15:
            // Cold-start path: app launched while a 15-min bypass is still in
            // flight. Keep the shield down and re-arm the OS schedule.
            let mins = max(1, Int(ceil(BlockingSessionService.shared.bypass15SecondsRemaining / 60)))
            screenTime.temporaryBypass(minutes: mins)
            isShieldActive = false

        case .dayBypass, .unlocked, .idle:
            if isShieldActive {
                screenTime.disengageMasterShield()
                isShieldActive = false
                logAuditEvent(type: .shieldDisengaged)
            }
        }
    }

    // MARK: - Solo Bypass Surface (called by AppBlockedShieldView)

    /// User wrote a justification note and is buying a 15-minute scroll window.
    func requestFifteenMinuteBypass(note: String) {
        let didCommit = BlockingSessionService.shared.requestFifteenMinuteBypass(note: note)
        guard didCommit else { return }
        screenTime.temporaryBypass(minutes: 15)
        isShieldActive = false
        isUnlocked = true
        // Pre-set the cached phase so syncShield() doesn't re-schedule the
        // DeviceActivity bypass window on the very next evaluatePolicy tick.
        lastBlockingPhase = .bypass15
        logAuditEvent(type: .selfRegBypass, notes: "15-min bypass: \(note)")
    }

    /// User has been shown their earlier note and confirmed an all-day bypass.
    func requestDayBypass() {
        BlockingSessionService.shared.requestDayBypass()
        screenTime.disengageMasterShield()
        isShieldActive = false
        isUnlocked = true
        lastBlockingPhase = .dayBypass
        let note = BlockingSessionService.shared.procrastinationNote
        logAuditEvent(type: .selfRegBypass,
                      notes: "Day bypass after reflection: \(note)")
    }

    // MARK: - Sync Gap Timer Fallback
    // Called when user taps "Syncing Data..." on the shield.
    func startSyncTimer() {
        isSyncTimerActive = true
        syncTimerRemainingSeconds = 60

        syncPollingTimer = Task {
            // Aggressive HealthKit poll while timer runs
            Task { await healthKit.aggressivePoll() }
            while syncTimerRemainingSeconds > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                syncTimerRemainingSeconds -= 1
                await evaluatePolicy()
                if isUnlocked { break }
            }
            isSyncTimerActive = false
        }
    }

    // MARK: - Grace Period (5 minutes — fail-soft for stale data)
    private func startGracePeriod() {
        isGracePeriodActive = true
        gracePeriodRemainingSeconds = 300
        screenTime.disengageMasterShield()
        logAuditEvent(type: .gracePeriod)

        gracePeriodTimer = Task {
            while gracePeriodRemainingSeconds > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                gracePeriodRemainingSeconds -= 1
            }
            isGracePeriodActive = false
            if !isUnlocked {
                screenTime.engageMasterShield()
            }
        }
    }

    // MARK: - Goal Editing (from Settings)
    func updateGoal(target: Double, currency: GoalCurrency) {
        activityGoal.agreedTarget = target
        activityGoal.currency = currency
        // Re-evaluate policy immediately with new goal
        Task { await evaluatePolicy() }
    }

    /// Copies negotiated goal fields from onboarding into the running dashboard model.
    func applyOnboardingGoal(_ goal: ActivityGoal) {
        activityGoal.agreedTarget = goal.agreedTarget
        activityGoal.currency = goal.currency
        activityGoal.hardCap = goal.hardCap
        activityGoal.recommendedTarget = goal.recommendedTarget
        Task { await evaluatePolicy() }
    }

    // MARK: - Master Shield Toggle (Single Radio Button)
    func toggleShield(enabled: Bool) {
        if enabled {
            screenTime.engageMasterShield()
            isShieldActive = true
            logAuditEvent(type: .shieldEngaged)
        } else {
            screenTime.disengageMasterShield()
            isShieldActive = false
            logAuditEvent(type: .shieldDisengaged)
        }
    }

    // MARK: - Break-Glass TOTP Validation
    func validateBreakGlassCode(_ code: String) async -> Bool {
        do {
            let isValid = try TOTPService.validateCode(code)
            if isValid {
                overrideState = OverrideState(
                    isActive: true,
                    expiresAt: Date().addingTimeInterval(15 * 60),
                    grantedByPartner: "Partner",
                    grantReason: "Break-Glass emergency override"
                )
                screenTime.breakGlassUnlock()
                logAuditEvent(type: .breakGlass)
            }
            return isValid
        } catch {
            print("[ActivityVM] TOTP validation error: \(error)")
            return false
        }
    }

    // MARK: - Self-Regulation Bypass (Motivational Friction)
    func requestSelfBypass(duration: Int, justification: String) {
        screenTime.temporaryBypass(minutes: duration)
        logAuditEvent(type: .selfRegBypass, notes: justification)
    }

    // MARK: - Partner Emergency Override (CloudKit-backed OTP)
    /// Apply an override grant the user just redeemed from their partner.
    /// Drops the master shield (and Sweat2Scroll's own grace/blocking phase)
    /// for exactly the granted duration, then re-engages the shield via the
    /// existing DeviceActivity bypass scheduling in `ScreenTimeService`.
    func applyEmergencyOverride(durationMinutes: Int,
                                grantedBy: String,
                                reason: String?) {
        let minutes = max(5, min(durationMinutes, 240))
        overrideState = OverrideState(
            isActive: true,
            expiresAt: Date().addingTimeInterval(TimeInterval(minutes * 60)),
            grantedByPartner: grantedBy,
            grantReason: reason ?? "Partner emergency override"
        )
        BlockingSessionService.shared.applyPartnerOverride(
            minutes: minutes,
            fromName: grantedBy,
            reason: reason
        )
        screenTime.temporaryBypass(minutes: minutes)
        logAuditEvent(type: .breakGlass, notes: reason)
    }

    // MARK: - Audit Logging
    private func logAuditEvent(type: AuditEventType, notes: String? = nil) {
        let event = AuditEvent(
            eventType: type,
            timestamp: Date(),
            entityID: "urn:uuid:shield-status",
            entityState: type.rawValue,
            agentID: "local-user",
            agentDisplayName: "You",
            caloriesAtEvent: healthKit.activeCaloriesToday,
            stepsAtEvent: healthKit.stepsToday,
            goalAtEvent: activityGoal.agreedTarget,
            overrideActive: overrideState.isValid,
            notes: notes
        )
        Task { await cloudKit.saveAuditEvent(event) }
    }
}
