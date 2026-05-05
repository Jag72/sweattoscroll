// Services/ScreenTimeService.swift
// Manages FamilyControls authorization, app selection, and shield enforcement.
// The single radio button maps to engageMasterShield() / disengageMasterShield().
// Persists FamilyActivitySelection in App Group for DeviceActivityMonitor extension.

import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
class ScreenTimeService: ObservableObject {

    // MARK: - Singleton
    static let shared = ScreenTimeService()

    private init() {
        refreshAuthorizationStatus()
        if let bid = Bundle.main.bundleIdentifier {
            sharedDefaults?.set(bid, forKey: AppGroupKey.hostAppBundleIdentifier)
        }
    }

    // MARK: - Published State
    @Published var isShieldActive: Bool = false
    @Published var activitySelection: FamilyActivitySelection = FamilyActivitySelection()
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined

    // MARK: - Private
    private let store = ManagedSettingsStore()
    private let activityCenter = DeviceActivityCenter()

    // MARK: - App Group for sharing tokens with extensions
    // IMPORTANT: Must match the App Group in Xcode entitlements
    private let appGroupID = "group.com.sweat2scroll.appblocker"
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // MARK: - Authorization
    enum AuthorizationStatus {
        case notDetermined, approved, denied
    }

    /// Syncs local status from `AuthorizationCenter` (call after app launch and when returning from Settings).
    func refreshAuthorizationStatus() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved:
            authorizationStatus = .approved
        case .denied:
            authorizationStatus = .denied
        case .notDetermined:
            authorizationStatus = .notDetermined
        @unknown default:
            authorizationStatus = .denied
        }
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshAuthorizationStatus()
        } catch {
            authorizationStatus = .denied
            AppLogger.screenTime.error("FamilyControls authorization failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Persist Selection to App Group
    // The DeviceActivityMonitor extension reads this from the shared container.
    /// Persists the selection after stripping the host app (`Sweat2Scroll`) so
    /// we never shield ourselves. Returns the sanitized value for binding sync.
    @discardableResult
    func saveSelection(_ selection: FamilyActivitySelection) -> FamilyActivitySelection {
        let cleaned = selection.excludingHostApplication()
        activitySelection = cleaned
        let data = try? PropertyListEncoder().encode(cleaned)
        sharedDefaults?.set(data, forKey: "activitySelection")
        sharedDefaults?.set(isShieldActive, forKey: "isShieldActive")
        return cleaned
    }

    func loadSelection() {
        guard let data = sharedDefaults?.data(forKey: "activitySelection"),
              let raw = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }
        // Migration / defense: strip host app if older builds persisted it.
        activitySelection = raw.excludingHostApplication()
        if activitySelection.applicationTokens.count != raw.applicationTokens.count {
            let cleanedData = try? PropertyListEncoder().encode(activitySelection)
            sharedDefaults?.set(cleanedData, forKey: "activitySelection")
        }
        isShieldActive = sharedDefaults?.bool(forKey: "isShieldActive") ?? false
    }

    // MARK: - Master Shield Toggle (Single Radio Button)
    /// Engages OS-level shields on all selected apps.
    /// Called when user flips the single master toggle ON.
    func engageMasterShield() {
        refreshAuthorizationStatus()
        guard authorizationStatus == .approved else {
            AppLogger.screenTime.warning("engageMasterShield skipped — Screen Time not approved.")
            return
        }
        let selection = activitySelection.excludingHostApplication()
        store.shield.applications = selection.applicationTokens
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(
            selection.categoryTokens
        )
        isShieldActive = true
        sharedDefaults?.set(true, forKey: "isShieldActive")
        AppLogger.screenTime.info("Master shield ENGAGED.")
    }

    /// Drops all OS-level shields instantly.
    /// Called by Wasm PDP when calorie goal is met, or Break-Glass is authorized.
    func disengageMasterShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        isShieldActive = false
        sharedDefaults?.set(false, forKey: "isShieldActive")
        AppLogger.screenTime.info("Master shield DISENGAGED.")
    }

    // MARK: - Temporary Bypass (1 min / 15 min options on shield)
    /// Temporarily drops shield for a specified duration, then re-engages.
    /// Uses DeviceActivityCenter for OS-level scheduling (survives app suspension)
    /// plus a Task-based fallback for cases where the app remains in the foreground.
    func temporaryBypass(minutes: Int) {
        disengageMasterShield()

        // Stop any previous bypass monitoring so its schedule doesn't overlap.
        activityCenter.stopMonitoring([.temporaryBypass])

        // Build a one-shot window that ends `minutes` from now.
        // DeviceActivityMonitor.intervalDidEnd fires in the extension process even
        // when the main app is suspended, ensuring reliable re-engagement.
        let now        = Date()
        let calendar   = Calendar.current
        let startComps = calendar.dateComponents([.hour, .minute, .second], from: now)
        let endDate    = calendar.date(byAdding: .minute, value: minutes, to: now) ?? now
        let endComps   = calendar.dateComponents([.hour, .minute, .second], from: endDate)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComps,
            intervalEnd:   endComps,
            repeats:       false
        )

        do {
            try activityCenter.startMonitoring(.temporaryBypass, during: schedule)
            AppLogger.screenTime.debug("DeviceActivity bypass window started: \(minutes) min.")
        } catch {
            // DeviceActivityCenter can fail on simulator — fall through to Task fallback.
            AppLogger.screenTime.error("DeviceActivity scheduling failed; using Task fallback: \(String(describing: error), privacy: .public)")
        }

        // Task-based fallback — also fires when the app is foregrounded.
        // Both paths call engageMasterShield(); the second call is idempotent.
        Task {
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            await MainActor.run { self.engageMasterShield() }
        }
    }

    // MARK: - Break-Glass Unlock (15 min TOTP override)
    func breakGlassUnlock() {
        disengageMasterShield()
        Task {
            try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000) // 15 min
            await MainActor.run { self.engageMasterShield() }
        }
        AppLogger.screenTime.info("Break-Glass 15-min window started.")
    }

    // MARK: - DeviceActivity Monitoring
    /// Starts monitoring for daily reset (midnight re-engagement)
    func startDailyMonitoring() {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        do {
            try activityCenter.startMonitoring(.daily, during: schedule)
        } catch {
            AppLogger.screenTime.error("DeviceActivity daily monitoring error: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Permission Check (for TamperDetectionService)
    func validatePermissions() -> Bool {
        return AuthorizationCenter.shared.authorizationStatus == .approved
    }
}

// MARK: - DeviceActivity Name Extension
extension DeviceActivityName {
    static let daily           = Self("com.sweat2scroll.daily")
    static let temporaryBypass = Self("com.sweat2scroll.bypass")
}
