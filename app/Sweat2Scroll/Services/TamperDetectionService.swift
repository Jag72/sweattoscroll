// Services/TamperDetectionService.swift
// Continuously monitors for adversarial bypass attempts:
//   1. HealthKit permission revocation
//   2. FamilyControls permission revocation
//   3. System clock manipulation (monotonic drift detection)
// On detection: logs PROV-DM tamper event + sends CloudKit alert to partner.

import Foundation
import FamilyControls

@MainActor
class TamperDetectionService: ObservableObject {

    // MARK: - Singleton
    static let shared = TamperDetectionService()

    // MARK: - Published State
    @Published var tamperDetected: Bool = false
    @Published var tamperType: AuditEventType?

    // MARK: - Monitoring State
    private var monitoringTask: Task<Void, Never>?
    private var lastWallClockTime: Date = Date()
    private var lastMonotonicTime: Double = ProcessInfo.processInfo.systemUptime
    private let checkIntervalSeconds: Double = 30   // Check every 30 seconds

    // Maximum allowable drift between wall clock and monotonic clock (in seconds)
    private let maxAllowableDrift: Double = 120

    // MARK: - Start Monitoring
    func startMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performChecks()
                try? await Task.sleep(nanoseconds: UInt64(self?.checkIntervalSeconds ?? 30) * 1_000_000_000)
            }
        }
        print("[TamperDetection] Watchdog started.")
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
    }

    // MARK: - Combined Checks
    private func performChecks() async {
        checkHealthKitPermissions()
        checkScreenTimePermissions()
        checkClockDrift()
    }

    // MARK: - "Ever-granted" gates
    //
    // We only call something a tamper if the user previously granted the
    // permission AND it's now revoked. On a fresh install (no permission
    // yet) the watchdog must NOT fire — otherwise every onboarding session
    // logs a false TAMPER_HEALTHKIT_REVOKED before the user even sees the
    // permission prompt, which is exactly what we observed in production
    // logs after wiring up the watchdog. The flags are flipped to true the
    // first time the corresponding service reports an authorized state, and
    // are persisted across launches via UserDefaults so re-installs that
    // restore prior auth still treat revocation as a tamper.
    private static let healthKitEverGrantedKey = "tamper.healthKitEverGranted"
    private static let screenTimeEverGrantedKey = "tamper.screenTimeEverGranted"

    private var healthKitEverGranted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.healthKitEverGrantedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.healthKitEverGrantedKey) }
    }

    private var screenTimeEverGranted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.screenTimeEverGrantedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.screenTimeEverGrantedKey) }
    }

    // MARK: - HealthKit Permission Check
    private func checkHealthKitPermissions() {
        let isValid = HealthKitService.shared.validatePermissions()
        if isValid {
            // Latch the "ever granted" flag the first time we see authorization.
            if !healthKitEverGranted { healthKitEverGranted = true }
            return
        }
        // Not currently authorized. Only treat as tamper if the user
        // previously authorized and has now revoked. Otherwise this is a
        // first-launch / pre-onboarding state and tamper would be a false
        // positive.
        guard healthKitEverGranted else { return }
        handleTamperEvent(type: .tamperHealthKit,
                          notes: "HealthKit activeEnergyBurned permission revoked.")
    }

    // MARK: - Screen Time Permission Check
    private func checkScreenTimePermissions() {
        let isApproved = AuthorizationCenter.shared.authorizationStatus == .approved
        if isApproved {
            if !screenTimeEverGranted { screenTimeEverGranted = true }
            return
        }
        guard screenTimeEverGranted else { return }
        handleTamperEvent(type: .tamperScreenTime,
                          notes: "FamilyControls authorization was revoked.")
    }

    // MARK: - Monotonic Clock Drift Detection
    // Compares wall clock delta vs monotonic clock delta.
    // A negative jump or large positive jump in wall clock = manual clock manipulation.
    private func checkClockDrift() {
        let currentWallClock = Date()
        let currentMonotonic = ProcessInfo.processInfo.systemUptime

        let wallDelta      = currentWallClock.timeIntervalSince(lastWallClockTime)
        let monotonicDelta = currentMonotonic - lastMonotonicTime

        let drift = abs(wallDelta - monotonicDelta)

        if drift > maxAllowableDrift {
            handleTamperEvent(type: .timeDrift,
                              notes: "Clock drift detected: \(Int(drift))s discrepancy between wall clock and monotonic clock.")
        }

        lastWallClockTime  = currentWallClock
        lastMonotonicTime  = currentMonotonic
    }

    // MARK: - Handle Tamper Event
    private func handleTamperEvent(type: AuditEventType, notes: String) {
        guard !tamperDetected else { return } // Avoid duplicate alerts

        tamperDetected = true
        tamperType = type

        print("[TamperDetection] ⚠️ TAMPER DETECTED: \(type.rawValue) — \(notes)")

        // Build PROV-DM audit event
        let event = AuditEvent(
            eventType: type,
            timestamp: Date(),
            entityID: "urn:uuid:shield-integrity",
            entityState: "COMPROMISED",
            agentID: "system-watchdog",
            agentDisplayName: "Sweat2Scroll Watchdog",
            caloriesAtEvent: 0,
            stepsAtEvent: 0,
            goalAtEvent: 0,
            overrideActive: false,
            notes: notes
        )

        // Dispatch tamper alert to partner via CloudKit (fire-and-forget)
        Task {
            await CloudKitService.shared.sendTamperAlert(event: event)
        }

        // Engage shields as fail-closed response
        Task { @MainActor in
            ScreenTimeService.shared.engageMasterShield()
        }
    }

    // MARK: - Time Drift State (queried by OPA policy input)
    var isTimeDriftDetected: Bool {
        let currentWall      = Date()
        let currentMonotonic = ProcessInfo.processInfo.systemUptime
        let wallDelta        = currentWall.timeIntervalSince(lastWallClockTime)
        let monotonicDelta   = currentMonotonic - lastMonotonicTime
        return abs(wallDelta - monotonicDelta) > maxAllowableDrift
    }
}
