// DeviceActivityMonitorExtension/Sweat2ScrollActivityMonitor.swift
// Runs in a separate sandboxed process (NOT the main app).
// Handles daily reset (midnight re-engagement of shields).
// Reads FamilyActivitySelection from the shared App Group container.

import Foundation          // UserDefaults, PropertyListDecoder
import DeviceActivity
import ManagedSettings
import FamilyControls

// The extension's principal class — declared in Info.plist
class Sweat2ScrollActivityMonitor: DeviceActivityMonitor {

    // MARK: - Shared App Group
    private let appGroupID = "group.com.sweat2scroll.appblocker"
    private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }
    private let store = ManagedSettingsStore()

    // MARK: - Daily Reset (intervalDidStart fires at midnight)
    // Re-engages shields at the start of a new day since yesterday's goal is reset.
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == .daily else { return }

        // Re-engage shield at start of new interval (midnight reset)
        engageShieldFromSharedContainer()
        print("[DeviceActivityMonitor] New day started. Shield re-engaged.")
    }

    // MARK: - Day End
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == .daily else { return }
        print("[DeviceActivityMonitor] Day interval ended.")
    }

    // MARK: - Event Threshold Reached
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        engageShieldFromSharedContainer()
    }

    // MARK: - Shield Enforcement (reads from App Group)
    private func engageShieldFromSharedContainer() {
        guard let data = sharedDefaults?.data(forKey: "activitySelection"),
              let raw = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            print("[DeviceActivityMonitor] No activity selection found in App Group.")
            return
        }

        let selection = Self.selectionRemovingHostApp(raw, sharedDefaults: sharedDefaults)

        let isShieldEnabled = sharedDefaults?.bool(forKey: "isShieldActive") ?? true

        if isShieldEnabled {
            store.shield.applications = selection.applicationTokens
            store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(
                selection.categoryTokens
            )
        }
    }

    /// Mirrors main-app sanitization — the `.appex` target cannot link the main
    /// app's `FamilyActivitySelection` helpers; uses `hostAppBundleIdentifier`
    /// from the App Group (written by the main app).
    private static func selectionRemovingHostApp(
        _ raw: FamilyActivitySelection,
        sharedDefaults: UserDefaults?
    ) -> FamilyActivitySelection {
        guard let host = sharedDefaults?.string(forKey: "hostAppBundleIdentifier")?.lowercased(),
              !host.isEmpty else {
            return raw
        }
        let filtered = raw.applicationTokens.filter {
            (Application(token: $0).bundleIdentifier?.lowercased() ?? "") != host
        }
        guard filtered.count != raw.applicationTokens.count else { return raw }
        var copy = raw
        copy.applicationTokens = Set(filtered)
        return copy
    }

    private func disengageShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }
}

// MARK: - DeviceActivityName Extension (must be duplicated here — extensions can't see main app code)
extension DeviceActivityName {
    static let daily           = Self("com.sweat2scroll.daily")
    static let temporaryBypass = Self("com.sweat2scroll.bypass")
}
