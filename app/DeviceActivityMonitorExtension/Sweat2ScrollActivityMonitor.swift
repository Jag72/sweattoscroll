// DeviceActivityMonitorExtension/Sweat2ScrollActivityMonitor.swift
// Runs in a separate sandboxed process (NOT the main app).
// Handles:
//   • Per-app 30-min usage thresholds (eventDidReachThreshold)
//   • Daily reset at midnight (clears exhaustion, drops shields)

import Foundation
import DeviceActivity
import ManagedSettings
import FamilyControls

class Sweat2ScrollActivityMonitor: DeviceActivityMonitor {

    private let appGroupID = "group.com.sweat2scroll.appblocker"
    private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }
    private let store = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        switch activity {
        case .daily:
            engageShieldFromSharedContainer()
            print("[DeviceActivityMonitor] New day started (legacy daily monitor).")

        case .perAppUsage:
            sharedDefaults?.removeObject(forKey: "usageMonitor.exhaustedAppIndices")
            sharedDefaults?.removeObject(forKey: "usageMonitor.exhaustedCatIndices")
            sharedDefaults?.removeObject(forKey: "blockingSession.graceEndsAt")
            disengageShield()
            print("[DeviceActivityMonitor] Per-app usage counters reset for new day.")

        default:
            break
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == .temporaryBypass {
            reconcileShields()
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity == .perAppUsage else {
            engageShieldFromSharedContainer()
            return
        }

        PerAppUsageMonitorBridge.markExhausted(
            eventName: event.rawValue,
            sharedDefaults: sharedDefaults
        )
        reconcileShields()
        print("[DeviceActivityMonitor] Usage threshold reached: \(event.rawValue)")
    }

    private func reconcileShields() {
        guard let defaults = sharedDefaults else { return }

        if defaults.bool(forKey: "blockingSession.goalReached") {
            disengageShield()
            return
        }

        let now = Date()
        if let dayEnd = defaults.object(forKey: "blockingSession.dayBypassEndsAt") as? Date, now < dayEnd {
            disengageShield()
            return
        }
        if let bypassEnd = defaults.object(forKey: "blockingSession.bypass15EndsAt") as? Date, now < bypassEnd {
            disengageShield()
            return
        }

        let exhaustedApps = PerAppUsageMonitorBridge.exhaustedApplicationTokens(defaults: defaults)
        let exhaustedCats = PerAppUsageMonitorBridge.exhaustedCategoryTokens(defaults: defaults)

        if exhaustedApps.isEmpty && exhaustedCats.isEmpty {
            disengageShield()
            return
        }

        store.shield.applications = exhaustedApps.isEmpty ? nil : exhaustedApps
        store.shield.applicationCategories = exhaustedCats.isEmpty
            ? nil
            : ShieldSettings.ActivityCategoryPolicy.specific(exhaustedCats)
        defaults.set(true, forKey: "isShieldActive")
    }

    private func engageShieldFromSharedContainer() {
        guard let data = sharedDefaults?.data(forKey: "activitySelection"),
              let raw = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }

        let selection = Self.selectionRemovingHostApp(raw, sharedDefaults: sharedDefaults)
        let isShieldEnabled = sharedDefaults?.bool(forKey: "isShieldActive") ?? true

        if isShieldEnabled {
            store.shield.applications = selection.applicationTokens
            store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(
                selection.categoryTokens
            )
        }
    }

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
        sharedDefaults?.set(false, forKey: "isShieldActive")
    }
}

extension DeviceActivityName {
    static let daily           = Self("com.sweat2scroll.daily")
    static let temporaryBypass = Self("com.sweat2scroll.bypass")
    static let perAppUsage      = Self("com.sweat2scroll.perAppUsage")
}

// MARK: - Index-based exhaustion bridge (duplicated for .appex target)

enum PerAppUsageMonitorBridge {
    static let appEventPrefix = "app.usage."
    static let catEventPrefix = "cat.usage."

    static func markExhausted(eventName: String, sharedDefaults: UserDefaults?) {
        guard let sharedDefaults else { return }

        if eventName.hasPrefix(appEventPrefix),
           let index = Int(eventName.dropFirst(appEventPrefix.count)) {
            appendIndex(index, key: "usageMonitor.exhaustedAppIndices", defaults: sharedDefaults)
        } else if eventName.hasPrefix(catEventPrefix),
                  let index = Int(eventName.dropFirst(catEventPrefix.count)) {
            appendIndex(index, key: "usageMonitor.exhaustedCatIndices", defaults: sharedDefaults)
        }
    }

    static func exhaustedApplicationTokens(defaults: UserDefaults) -> Set<ApplicationToken> {
        let apps = loadManifestApplicationTokens(defaults: defaults)
        let indices = defaults.array(forKey: "usageMonitor.exhaustedAppIndices") as? [Int] ?? []
        var result = Set<ApplicationToken>()
        for i in indices where i >= 0 && i < apps.count {
            result.insert(apps[i])
        }
        return result
    }

    static func exhaustedCategoryTokens(defaults: UserDefaults) -> Set<ActivityCategoryToken> {
        let cats = loadManifestCategoryTokens(defaults: defaults)
        let indices = defaults.array(forKey: "usageMonitor.exhaustedCatIndices") as? [Int] ?? []
        var result = Set<ActivityCategoryToken>()
        for i in indices where i >= 0 && i < cats.count {
            result.insert(cats[i])
        }
        return result
    }

    private static func loadManifestApplicationTokens(defaults: UserDefaults) -> [ApplicationToken] {
        guard let dataArray = defaults.array(forKey: "usageMonitor.appTokenData") as? [Data] else {
            return []
        }
        return dataArray.compactMap { try? PropertyListDecoder().decode(ApplicationToken.self, from: $0) }
    }

    private static func loadManifestCategoryTokens(defaults: UserDefaults) -> [ActivityCategoryToken] {
        guard let dataArray = defaults.array(forKey: "usageMonitor.catTokenData") as? [Data] else {
            return []
        }
        return dataArray.compactMap { try? PropertyListDecoder().decode(ActivityCategoryToken.self, from: $0) }
    }

    private static func appendIndex(_ index: Int, key: String, defaults: UserDefaults) {
        var existing = defaults.array(forKey: key) as? [Int] ?? []
        guard !existing.contains(index) else { return }
        existing.append(index)
        defaults.set(existing, forKey: key)
    }
}
