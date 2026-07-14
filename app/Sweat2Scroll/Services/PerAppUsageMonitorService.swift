// PerAppUsageMonitorService.swift
// Tracks **per-app** (and per-category) daily screen-time usage via
// DeviceActivityEvent thresholds. Each selected app gets its own 30-minute
// allowance — Instagram and Facebook are counted separately, and the timer
// starts when the user actually opens that app, not when Sweat2Scroll launches.

import Foundation
import Combine
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
final class PerAppUsageMonitorService: ObservableObject {

    static let shared = PerAppUsageMonitorService()

    /// Daily active-use allowance per selected app/category (minutes).
    static let limitMinutes: Int = 30

    @Published private(set) var exhaustedAppCount: Int = 0
    @Published private(set) var monitoredAppCount: Int = 0

    private let appGroupID = "group.com.sweat2scroll.appblocker"
    private let activityCenter = DeviceActivityCenter()

    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    private init() {
        refreshPublishedCounts(selection: ScreenTimeService.shared.activitySelection)
    }

    // MARK: - Monitoring lifecycle

    func refreshMonitoring(for selection: FamilyActivitySelection) {
        let cleaned = selection.excludingHostApplication()
        stopMonitoring()

        let appTokens = Array(cleaned.applicationTokens)
        let catTokens = Array(cleaned.categoryTokens)
        monitoredAppCount = appTokens.count + catTokens.count

        guard monitoredAppCount > 0 else {
            persistTokenManifest(appTokens: [], catTokens: [])
            refreshPublishedCounts(selection: cleaned)
            return
        }

        let manifestDirty = manifestChanged(appTokens: appTokens, catTokens: catTokens)
        persistTokenManifest(appTokens: appTokens, catTokens: catTokens)

        if manifestDirty {
            defaults?.removeObject(forKey: AppGroupKey.exhaustedAppIndices)
            defaults?.removeObject(forKey: AppGroupKey.exhaustedCatIndices)
        }

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        let threshold = DateComponents(minute: Self.limitMinutes)

        for (index, token) in appTokens.enumerated() {
            let name = DeviceActivityEvent.Name("\(Self.appEventPrefix)\(index)")
            events[name] = DeviceActivityEvent(applications: [token], threshold: threshold)
        }
        for (index, token) in catTokens.enumerated() {
            let name = DeviceActivityEvent.Name("\(Self.catEventPrefix)\(index)")
            events[name] = DeviceActivityEvent(categories: [token], threshold: threshold)
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )

        do {
            try activityCenter.startMonitoring(
                .perAppUsage,
                during: schedule,
                events: events
            )
            AppLogger.screenTime.info("Per-app usage monitoring started for \(self.monitoredAppCount) target(s).")
        } catch {
            AppLogger.screenTime.error("Per-app monitoring failed: \(String(describing: error), privacy: .public)")
        }

        refreshPublishedCounts(selection: cleaned)
    }

    func stopMonitoring() {
        activityCenter.stopMonitoring([.perAppUsage])
    }

    func resetDailyExhaustion() {
        defaults?.removeObject(forKey: AppGroupKey.exhaustedAppIndices)
        defaults?.removeObject(forKey: AppGroupKey.exhaustedCatIndices)
        exhaustedAppCount = 0
        refreshPublishedCounts(selection: ScreenTimeService.shared.activitySelection)
    }

    // MARK: - Exhaustion queries (main app)

    func loadExhaustedApplicationTokens(from selection: FamilyActivitySelection) -> Set<ApplicationToken> {
        let apps = loadManifestApplicationTokens()
        let indices = loadExhaustedAppIndices()
        var exhausted = Set<ApplicationToken>()
        for i in indices where i >= 0 && i < apps.count {
            exhausted.insert(apps[i])
        }
        // Only shield tokens still in the current selection.
        return exhausted.intersection(selection.applicationTokens)
    }

    func loadExhaustedCategoryTokens(from selection: FamilyActivitySelection) -> Set<ActivityCategoryToken> {
        let cats = loadManifestCategoryTokens()
        let indices = loadExhaustedCatIndices()
        var exhausted = Set<ActivityCategoryToken>()
        for i in indices where i >= 0 && i < cats.count {
            exhausted.insert(cats[i])
        }
        return exhausted.intersection(selection.categoryTokens)
    }

    func allTargetsExhausted(for selection: FamilyActivitySelection) -> Bool {
        let cleaned = selection.excludingHostApplication()
        let total = cleaned.applicationTokens.count + cleaned.categoryTokens.count
        guard total > 0 else { return false }
        return loadExhaustedAppIndices().count + loadExhaustedCatIndices().count >= total
    }

    func refreshPublishedCounts(selection: FamilyActivitySelection) {
        let cleaned = selection.excludingHostApplication()
        monitoredAppCount = cleaned.applicationTokens.count + cleaned.categoryTokens.count
        exhaustedAppCount = loadExhaustedAppIndices().count + loadExhaustedCatIndices().count
    }

    // MARK: - Extension callbacks (static — runs in .appex process)

    static let appEventPrefix = "app.usage."
    static let catEventPrefix = "cat.usage."

    static func markExhausted(eventName: String, sharedDefaults: UserDefaults?) {
        guard let sharedDefaults else { return }

        if eventName.hasPrefix(appEventPrefix),
           let index = Int(eventName.dropFirst(appEventPrefix.count)) {
            appendIndex(index, key: AppGroupKey.exhaustedAppIndices, defaults: sharedDefaults)
        } else if eventName.hasPrefix(catEventPrefix),
                  let index = Int(eventName.dropFirst(catEventPrefix.count)) {
            appendIndex(index, key: AppGroupKey.exhaustedCatIndices, defaults: sharedDefaults)
        }
    }

    // MARK: - Token manifest persistence

    /// Stores the monitored token order so indices from DeviceActivity events
    /// map back to the correct app/category at shield time.
    private func persistTokenManifest(appTokens: [ApplicationToken], catTokens: [ActivityCategoryToken]) {
        let encoder = PropertyListEncoder()
        let appData = appTokens.compactMap { try? encoder.encode($0) }
        let catData = catTokens.compactMap { try? encoder.encode($0) }
        defaults?.set(appData, forKey: AppGroupKey.usageMonitorAppTokenData)
        defaults?.set(catData, forKey: AppGroupKey.usageMonitorCatTokenData)
    }

    private func loadExhaustedAppIndices() -> [Int] {
        defaults?.array(forKey: AppGroupKey.exhaustedAppIndices) as? [Int] ?? []
    }

    private func loadExhaustedCatIndices() -> [Int] {
        defaults?.array(forKey: AppGroupKey.exhaustedCatIndices) as? [Int] ?? []
    }

    private func loadManifestApplicationTokens() -> [ApplicationToken] {
        guard let dataArray = defaults?.array(forKey: AppGroupKey.usageMonitorAppTokenData) as? [Data] else {
            return []
        }
        let decoder = PropertyListDecoder()
        return dataArray.compactMap { try? decoder.decode(ApplicationToken.self, from: $0) }
    }

    private func loadManifestCategoryTokens() -> [ActivityCategoryToken] {
        guard let dataArray = defaults?.array(forKey: AppGroupKey.usageMonitorCatTokenData) as? [Data] else {
            return []
        }
        let decoder = PropertyListDecoder()
        return dataArray.compactMap { try? decoder.decode(ActivityCategoryToken.self, from: $0) }
    }

    private static func appendIndex(_ index: Int, key: String, defaults: UserDefaults) {
        var existing = defaults.array(forKey: key) as? [Int] ?? []
        guard !existing.contains(index) else { return }
        existing.append(index)
        defaults.set(existing, forKey: key)
    }

    private func manifestChanged(appTokens: [ApplicationToken], catTokens: [ActivityCategoryToken]) -> Bool {
        let encoder = PropertyListEncoder()
        let newApp = appTokens.compactMap { try? encoder.encode($0) }
        let newCat = catTokens.compactMap { try? encoder.encode($0) }
        let oldApp = defaults?.array(forKey: AppGroupKey.usageMonitorAppTokenData) as? [Data] ?? []
        let oldCat = defaults?.array(forKey: AppGroupKey.usageMonitorCatTokenData) as? [Data] ?? []
        return newApp != oldApp || newCat != oldCat
    }
}

extension DeviceActivityName {
    static let perAppUsage = Self("com.sweat2scroll.perAppUsage")
}
