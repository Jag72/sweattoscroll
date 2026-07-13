// Services/HealthKitService.swift
// Handles all HealthKit authorization, queries, and background delivery.
// Reads: activeEnergyBurned, stepCount, bodyMass, height, dateOfBirth, biologicalSex.
// Configures HKObserverQuery + enableBackgroundDelivery (hourly max per Apple limits).

import Foundation
import HealthKit

@MainActor
class HealthKitService: ObservableObject {

    /// Shared singleton — every VM should read through this to keep HK data
    /// coherent across the app instead of spawning duplicate stores.
    static let shared = HealthKitService()

    // MARK: - Published State
    @Published var isAuthorized: Bool = false
    @Published var activeCaloriesToday: Double = 0
    @Published var stepsToday: Int = 0
    @Published var heartRateLatest: Double = 0 // bpm — most recent heart rate sample today
    @Published var userProfile: UserProfile?
    /// True when height / weight / age are not fully available from HealthKit and
    /// no valid manual save exists — user should complete manual onboarding or Profile.
    @Published var needsManualBodyMetrics: Bool = false
    @Published var lastSyncDate: Date = .distantPast
    @Published var isHealthKitAvailable: Bool = HKHealthStore.isHealthDataAvailable()

    // MARK: - Wellness Metrics (for WellnessViewModel)
    @Published var hrvSDNN: Double = 0          // ms — heartRateVariabilitySDNN
    @Published var restingHeartRate: Double = 0 // bpm
    @Published var respiratoryRate: Double = 0  // breaths/min
    @Published var sleepMinutesLast: Double = 0 // total sleep (asleep stages) last night, in minutes

    // MARK: - Apple Activity Rings (for "Energy" score)
    @Published var exerciseMinutesToday: Double = 0 // minutes of brisk activity today
    @Published var standHoursToday: Double = 0      // hours stood at least 1 min today

    // MARK: - 7-Day History (oldest → today)
    @Published var calorieHistory: [Double] = Array(repeating: 0, count: 7)
    @Published var stepsHistory:   [Double] = Array(repeating: 0, count: 7)
    @Published var sleepHistory:   [Double] = Array(repeating: 0, count: 7) // minutes per day
    @Published var hrvHistory:     [Double] = Array(repeating: 0, count: 7)
    @Published var rhrHistory:     [Double] = Array(repeating: 0, count: 7)
    @Published var respHistory:    [Double] = Array(repeating: 0, count: 7)
    @Published var exerciseHistory: [Double] = Array(repeating: 0, count: 7) // minutes
    @Published var standHistory:    [Double] = Array(repeating: 0, count: 7) // hours

    // MARK: - Private
    private let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?
    private var backgroundDeliveryEnabled: Bool = false

    // MARK: - HealthKit Types Required
    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.stepCount),
        HKQuantityType(.bodyMass),
        HKQuantityType(.height),
        HKQuantityType(.heartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.respiratoryRate),
        HKQuantityType(.appleExerciseTime),
        HKQuantityType(.appleStandTime),
        HKCategoryType(.appleStandHour),
        HKCategoryType(.sleepAnalysis),
        HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
        HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
    ]

    // MARK: - Authorization

    /// True when the user has explicitly denied write access for *every* read
    /// type — a strong signal we should send them to Settings → Health.
    /// (iOS doesn't expose read-status programmatically; we use writes as a
    /// proxy and combine with `hasAnyDataForToday()` for confirmation.)
    ///
    /// Deprecated for read-only apps: iOS always reports `.sharingDenied` for
    /// read-only types, so this flag is never raised — see `verifyAccess()`.
    @Published var allTypesDenied: Bool = false

    /// True once iOS reports the HealthKit permission sheet has already been
    /// shown for our read set (`.unnecessary`). For read-only apps this is the
    /// only reliable signal that the user responded — iOS intentionally hides
    /// whether individual read categories were granted.
    @Published private(set) var hasAnsweredAuthorizationPrompt: Bool = false

    /// Asks HealthKit for read access. iOS only shows the system sheet the
    /// first time per (bundle id, type-set); subsequent calls are a no-op even
    /// if the user denied — we surface that case via `verifyAccess()`.
    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        await verifyAccess()
        // Profile + today's metrics are best-effort — a query failure (common on
        // Simulator, or before the user has moved today) must NOT be treated as
        // "access denied" and block onboarding.
        try? await fetchUserProfile()
        try? await fetchTodayMetrics()
        // If the user already answered the prompt, treat Health as connected
        // even when today's calorie/step totals are still 0.
        if hasAnsweredAuthorizationPrompt {
            isAuthorized = true
        }
        setupBackgroundDelivery()
    }

    /// Determines whether we should treat HealthKit as usable.
    ///
    /// IMPORTANT: For a **read-only** app, `authorizationStatus(for:)` (which
    /// reports *share/write* permission) is meaningless — iOS returns
    /// `.sharingDenied` for every read-only type on purpose, so it never leaks
    /// whether the user allowed reads. Using it as a denial signal produced a
    /// false "Apple Health is blocking access" banner whenever today's active
    /// calories/steps happened to be 0 (e.g. the Simulator, or before the user
    /// has moved), even though profile reads were working fine.
    ///
    /// Instead we ask iOS whether it still needs to prompt us. `.unnecessary`
    /// means the user has already responded to our authorization request — at
    /// which point we assume access is fine, because HealthKit gives us no way
    /// to distinguish "denied read" from "no samples yet", and a false alarm is
    /// worse than silently offering manual entry.
    func verifyAccess() async {
        guard isHealthKitAvailable else {
            isAuthorized = false
            hasAnsweredAuthorizationPrompt = false
            allTypesDenied = false
            return
        }

        let requestStatus = await requestStatusForAuthorization()
        hasAnsweredAuthorizationPrompt = (requestStatus == .unnecessary)

        switch requestStatus {
        case .unnecessary:
            // User already responded to our prompt (granted or denied — iOS won't
            // tell us for reads). Treat as connected; manual entry covers gaps.
            isAuthorized = true
        case .shouldRequest:
            // Haven't shown the sheet yet — only claim authorized if profile
            // samples are already flowing (e.g. restored session).
            isAuthorized = userProfile != nil && !needsManualBodyMetrics
        @unknown default:
            isAuthorized = hasAnsweredAuthorizationPrompt
        }
        // Never hard-flag "denied" from read-only signals — it can't be detected
        // reliably and previously fired false positives.
        allTypesDenied = false
    }

    /// Wraps `getRequestStatusForAuthorization` in async/await. Returns whether
    /// iOS would still show the permission sheet for our read set.
    private func requestStatusForAuthorization() async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Fetch User Profile (biometrics for CalorieEngine)
    /// Merges Apple Health samples with values saved in-app (onboarding / Profile).
    func fetchUserProfile() async throws {
        await mergeUserProfileFromSources()
    }

    /// Persists manual edits and recomputes `userProfile` (used by onboarding + Profile editor).
    func applyManualBodyMetrics(heightCm: Double, weightKg: Double, ageYears: Int, biologicalSex: BiologicalSex) async {
        UserBodyProfileStorage.save(
            heightCm: heightCm,
            weightKg: weightKg,
            ageYears: ageYears,
            biologicalSex: biologicalSex
        )
        await mergeUserProfileFromSources()
    }

    /// Merges HK quantities + characteristic types with `UserBodyProfileStorage`.
    private func mergeUserProfileFromSources() async {
        let weightHK = try? await fetchMostRecentQuantity(
            type: .init(.bodyMass),
            unit: .gramUnit(with: .kilo)
        )
        let heightHK = try? await fetchMostRecentQuantity(
            type: .init(.height),
            unit: .meterUnit(with: .centi)
        )
        let ageHK = ageYearsFromDateOfBirth()
        let sexHK = biologicalSexFromHealthKit()

        let saved = UserBodyProfileStorage.load()

        let mergedWeight = weightHK ?? saved.weightKg
        let mergedHeight = heightHK ?? saved.heightCm
        let mergedAge = ageHK ?? saved.ageYears
        let mergedSex = sexHK ?? saved.biologicalSex ?? .other

        let complete = Self.metricsAreComplete(weightKg: mergedWeight, heightCm: mergedHeight, ageYears: mergedAge)
        needsManualBodyMetrics = !complete

        // Safe defaults only fill gaps until the user saves valid manual values.
        let weightFinal = mergedWeight ?? 70
        let heightFinal = mergedHeight ?? 170
        let ageFinal = mergedAge ?? 30

        userProfile = UserProfile(
            weightKg: weightFinal,
            heightCm: heightFinal,
            ageYears: ageFinal,
            biologicalSex: mergedSex,
            goalCurrency: .activeCalories
        )
    }

    private static func metricsAreComplete(weightKg: Double?, heightCm: Double?, ageYears: Int?) -> Bool {
        guard let w = weightKg, let h = heightCm, let a = ageYears else { return false }
        return w >= 30 && w <= 250 && h >= 120 && h <= 230 && a >= 13 && a <= 110
    }

    private func ageYearsFromDateOfBirth() -> Int? {
        guard let comps = try? store.dateOfBirthComponents() else { return nil }
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return nil }
        var dc = DateComponents()
        dc.year = y
        dc.month = m
        dc.day = d
        guard let birth = Calendar.current.date(from: dc) else { return nil }
        let years = Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 0
        guard years >= 13 && years <= 110 else { return nil }
        return years
    }

    private func biologicalSexFromHealthKit() -> BiologicalSex? {
        guard let hkSex = try? store.biologicalSex().biologicalSex else { return nil }
        switch hkSex {
        case .male:   return .male
        case .female: return .female
        case .notSet: return nil
        @unknown default:
            return .other
        }
    }

    // MARK: - Fetch Today's Metrics
    func fetchTodayMetrics() async throws {
        activeCaloriesToday = try await fetchTodaySum(
            type: .init(.activeEnergyBurned),
            unit: .kilocalorie()
        )
        stepsToday = Int(try await fetchTodaySum(
            type: .init(.stepCount),
            unit: .count()
        ))
        // Apple Exercise Time (minutes) and Stand Time (seconds → hours).
        exerciseMinutesToday = (try? await fetchTodaySum(
            type: .init(.appleExerciseTime), unit: .minute()
        )) ?? exerciseMinutesToday
        let standSeconds = (try? await fetchTodaySum(
            type: .init(.appleStandTime), unit: .second()
        )) ?? 0
        if standSeconds > 0 {
            standHoursToday = standSeconds / 3600.0
        } else {
            // Fallback to category samples (each sample is one stand-hour).
            standHoursToday = await fetchTodayStandHourCount()
        }
        // Most recent heart-rate sample (today only) — used by Home tile.
        if let hr = try? await fetchMostRecentQuantityToday(
            type: .init(.heartRate),
            unit: HKUnit(from: "count/min")
        ) {
            heartRateLatest = hr ?? heartRateLatest
        }
        lastSyncDate = Date()
    }

    /// Number of stand hours logged today via `appleStandHour` category samples.
    /// Used as a fallback when `appleStandTime` returns no rows on older watchOS.
    private func fetchTodayStandHourCount() async -> Double {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        return await withCheckedContinuation { continuation in
            let q = HKSampleQuery(
                sampleType: HKCategoryType(.appleStandHour),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: 0); return
                }
                let stood = samples.filter {
                    $0.value == HKCategoryValueAppleStandHour.stood.rawValue
                }.count
                continuation.resume(returning: Double(stood))
            }
            store.execute(q)
        }
    }

    /// Fetches the last 7 calendar days of cumulative metrics + per-day averages
    /// for HRV, RHR, respiratory rate, sleep, exercise minutes, and stand hours.
    /// Index 0 = 6 days ago, 6 = today.
    func fetchWeeklyHistory() async {
        async let calories = fetchDailySumHistory(type: .init(.activeEnergyBurned), unit: .kilocalorie(), days: 7)
        async let steps    = fetchDailySumHistory(type: .init(.stepCount),         unit: .count(),        days: 7)
        async let hrvVals  = fetchDailyAverageHistory(type: .init(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), days: 7)
        async let rhrVals  = fetchDailyAverageHistory(type: .init(.restingHeartRate),         unit: HKUnit(from: "count/min"), days: 7)
        async let respVals = fetchDailyAverageHistory(type: .init(.respiratoryRate),          unit: HKUnit(from: "count/min"), days: 7)
        async let exMins   = fetchDailySumHistory(type: .init(.appleExerciseTime), unit: .minute(), days: 7)
        async let standSec = fetchDailySumHistory(type: .init(.appleStandTime),    unit: .second(), days: 7)
        async let sleep    = fetchDailySleepHistory(days: 7)

        let (cals, stps, hrvs, rhrs, resps, exs, std, slps) = await (
            calories, steps, hrvVals, rhrVals, respVals, exMins, standSec, sleep
        )

        calorieHistory  = cals
        stepsHistory    = stps
        hrvHistory      = hrvs
        rhrHistory      = rhrs
        respHistory     = resps
        exerciseHistory = exs
        standHistory    = std.map { $0 / 3600.0 } // seconds → hours
        sleepHistory    = slps
    }

    // MARK: - Fetch Wellness Metrics (HRV, RHR, Respiratory Rate, Sleep)
    // Call from WellnessViewModel to load live data for the WHOOP-style dashboard.
    // These are typically updated by Apple Watch during overnight charging.
    func fetchWellnessMetrics() async {
        async let hrv         = fetchMostRecentQuantity(type: .init(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli))
        async let rhr         = fetchMostRecentQuantity(type: .init(.restingHeartRate),         unit: HKUnit(from: "count/min"))
        async let resp        = fetchMostRecentQuantity(type: .init(.respiratoryRate),           unit: HKUnit(from: "count/min"))
        async let sleepMins   = fetchSleepMinutesLastNight()

        let (hrvVal, rhrVal, respVal, sleepVal) = await (
            (try? hrv) ?? nil,
            (try? rhr) ?? nil,
            (try? resp) ?? nil,
            sleepMins
        )

        if let v = hrvVal  { hrvSDNN          = v }
        if let v = rhrVal  { restingHeartRate = v }
        if let v = respVal { respiratoryRate  = v }
        sleepMinutesLast = sleepVal
    }

    // MARK: - Sleep Analysis (last night's total asleep time)
    // Sums HKCategoryValueSleepAnalysis samples for the most recent sleep window
    // (from previous day's 6 PM to current day's 12 PM) so we catch all watch-tracked stages.
    private func fetchSleepMinutesLastNight() async -> Double {
        let now        = Date()
        let calendar   = Calendar.current
        let todayNoon  = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        // Previous evening starting point (6 PM yesterday)
        let yesterday  = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let startOfWindow = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday) ?? yesterday

        let predicate = HKQuery.predicateForSamples(withStart: startOfWindow, end: todayNoon)
        let sleepType = HKCategoryType(.sleepAnalysis)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: 0)
                    return
                }
                // Sum only samples where the user was actually asleep (excludes InBed)
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let totalSeconds = samples
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: totalSeconds / 60.0)
            }
            store.execute(query)
        }
    }

    // MARK: - Background Delivery
    // Apple throttles background delivery for stepCount and activeEnergyBurned to hourly.
    // This is the maximum allowed frequency — cannot be configured to real-time.
    private func setupBackgroundDelivery() {
        guard !backgroundDeliveryEnabled else { return }

        let types: [(HKQuantityTypeIdentifier, HKUpdateFrequency)] = [
            (.activeEnergyBurned, .hourly),
            (.stepCount, .hourly)
        ]

        for (identifier, frequency) in types {
            let quantityType = HKQuantityType(identifier)
            store.enableBackgroundDelivery(for: quantityType, frequency: frequency) { success, error in
                if let error { print("[HealthKit] Background delivery error: \(error)") }
            }

            let query = HKObserverQuery(sampleType: quantityType, predicate: nil) { [weak self] _, _, error in
                guard error == nil else { return }
                Task { @MainActor [weak self] in
                    try? await self?.fetchTodayMetrics()
                }
            }
            store.execute(query)
        }
        backgroundDeliveryEnabled = true
    }

    // MARK: - Aggressive Foreground Poll (used by Timer Fallback UI)
    // Called when user taps "Syncing Data..." on the shield.
    // Forces HealthKit to prioritize BLE sync from Apple Watch.
    func aggressivePoll() async {
        for _ in 0..<5 {
            try? await fetchTodayMetrics()
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second intervals
        }
    }

    // MARK: - Helpers
    private func fetchTodaySum(type: HKQuantityType, unit: HKUnit) async throws -> Double {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        // .strictStartDate ensures we only count samples whose START is in
        // today's window — matches the rounding the iOS Fitness app uses.
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: now,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchMostRecentQuantity(type: HKQuantityType, unit: HKUnit) async throws -> Double? {
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func fetchMostRecentQuantityToday(type: HKQuantityType, unit: HKUnit) async throws -> Double? {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: now,
            options: .strictStartDate
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// Returns N values, one per day from `days-1` days ago through today.
    /// Uses cumulative sum (e.g. calories, steps).
    func fetchDailySumHistory(type: HKQuantityType, unit: HKUnit, days: Int) async -> [Double] {
        await fetchDailyHistory(type: type, unit: unit, days: days, options: .cumulativeSum, picker: { $0.sumQuantity()?.doubleValue(for: unit) })
    }

    /// Returns N values, one per day. Uses discrete average (e.g. HRV, RHR, respiratory rate).
    func fetchDailyAverageHistory(type: HKQuantityType, unit: HKUnit, days: Int) async -> [Double] {
        await fetchDailyHistory(type: type, unit: unit, days: days, options: .discreteAverage, picker: { $0.averageQuantity()?.doubleValue(for: unit) })
    }

    /// Public sleep history fetcher for arbitrary day windows.
    func fetchSleepHistory(days: Int) async -> [Double] {
        await fetchDailySleepHistory(days: days)
    }

    private func fetchDailyHistory(type: HKQuantityType, unit: HKUnit, days: Int,
                                   options: HKStatisticsOptions,
                                   picker: @escaping (HKStatistics) -> Double?) async -> [Double] {
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: Date())) ?? Date()

        return await withCheckedContinuation { continuation in
            let interval = DateComponents(day: 1)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: nil,
                options: options,
                anchorDate: start,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                var values = Array(repeating: 0.0, count: days)
                results?.enumerateStatistics(from: start, to: endOfToday) { stat, _ in
                    let dayIdx = calendar.dateComponents([.day], from: start, to: stat.startDate).day ?? 0
                    if dayIdx >= 0 && dayIdx < days {
                        values[dayIdx] = picker(stat) ?? 0
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    /// Returns sleep minutes per day for the last N days (index 0 = oldest).
    func fetchDailySleepHistory(days: Int) async -> [Double] {
        let calendar = Calendar.current
        let now = Date()
        let sleepType = HKCategoryType(.sleepAnalysis)

        var values = Array(repeating: 0.0, count: days)
        for offset in 0..<days {
            let dayEnd = calendar.date(bySettingHour: 12, minute: 0, second: 0,
                                       of: calendar.date(byAdding: .day, value: -(days - 1 - offset), to: now) ?? now) ?? now
            let dayStart = calendar.date(byAdding: .hour, value: -18, to: dayEnd) ?? dayEnd
            let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd)
            let mins: Double = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                          limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                    guard let samples = samples as? [HKCategorySample] else {
                        continuation.resume(returning: 0); return
                    }
                    let asleepValues: Set<Int> = [
                        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                        HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    ]
                    let total = samples.filter { asleepValues.contains($0.value) }
                        .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                    continuation.resume(returning: total / 60.0)
                }
                store.execute(query)
            }
            values[offset] = mins
        }
        return values
    }

    // MARK: - Permission Validation (for TamperDetectionService)
    func validatePermissions() -> Bool {
        let status = store.authorizationStatus(for: HKQuantityType(.activeEnergyBurned))
        return status == .sharingAuthorized
    }
}

// MARK: - Errors
enum HealthKitError: LocalizedError {
    case notAvailable
    case authorizationDenied
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:       return "HealthKit is not available on this device."
        case .authorizationDenied: return "HealthKit authorization was denied."
        case .queryFailed(let m): return "HealthKit query failed: \(m)"
        }
    }
}
