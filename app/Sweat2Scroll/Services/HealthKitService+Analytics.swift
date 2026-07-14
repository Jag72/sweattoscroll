// Services/HealthKitService+Analytics.swift
// Extra HealthKit queries powering the analytics page + WellnessAlgorithms:
//   • minute-bucketed heart rate (for Banister TRIMP strain)
//   • detailed sleep nights with stages + bedtimes (for the sleep score)
//   • hourly today series (for the "D" range on the analytics charts)
//
// Kept in an extension with its own HKHealthStore so the main service file
// stays untouched; HKHealthStore instances all read the same on-device store.

import Foundation
import HealthKit

extension HealthKitService {

    private static let analyticsStore = HKHealthStore()

    // MARK: - Minute-bucketed heart rate (today or any window)

    /// Average heart rate per minute across `start..<end`, as `HRSample`s with
    /// minutes-offset from `start`. Empty minutes are skipped so TRIMP's Δt cap
    /// handles gaps correctly.
    func fetchMinuteHeartRate(start: Date, end: Date) async -> [HRSample] {
        guard isHealthKitAvailable else { return [] }
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end,
                                                    options: .strictStartDate)
        var interval = DateComponents(); interval.minute = 1

        return await withCheckedContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: Calendar.current.startOfDay(for: start),
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                var out: [HRSample] = []
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let avg = stats.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min")) {
                        let offset = stats.startDate.timeIntervalSince(start) / 60.0
                        out.append(HRSample(minuteOffset: offset, bpm: avg))
                    }
                }
                cont.resume(returning: out)
            }
            Self.analyticsStore.execute(query)
        }
    }

    // MARK: - Detailed sleep night (stages + bedtime)

    /// The most recent full night (6 pm yesterday → 6 pm today window), with
    /// stage breakdown when the source provides it (Apple Watch does).
    func fetchLastSleepNight() async -> SleepNight? {
        let nights = await fetchSleepNights(days: 1)
        return nights.last ?? nil
    }

    /// One `SleepNight?` per day, oldest → newest. A day's "night" is the
    /// window ending 6 pm that day (so Tuesday's entry = Monday night).
    func fetchSleepNights(days: Int) async -> [SleepNight?] {
        guard isHealthKitAvailable else { return Array(repeating: nil, count: days) }
        let type = HKCategoryType(.sleepAnalysis)
        let calendar = Calendar.current
        let today6pm = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
        let windowStart = calendar.date(byAdding: .day, value: -days, to: today6pm) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: today6pm, options: [])

        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, _ in
                cont.resume(returning: (s as? [HKCategorySample]) ?? [])
            }
            Self.analyticsStore.execute(q)
        }

        var nights: [SleepNight?] = []
        for dayOffset in (0..<days).reversed() {
            let nightEnd = calendar.date(byAdding: .day, value: -dayOffset, to: today6pm)!
            let nightStart = calendar.date(byAdding: .day, value: -1, to: nightEnd)!
            let nightSamples = samples.filter { $0.startDate >= nightStart && $0.startDate < nightEnd }
            nights.append(Self.buildNight(from: nightSamples, calendar: calendar))
        }
        return nights
    }

    private static func buildNight(from samples: [HKCategorySample], calendar: Calendar) -> SleepNight? {
        guard !samples.isEmpty else { return nil }

        func minutes(_ s: HKCategorySample) -> Double {
            s.endDate.timeIntervalSince(s.startDate) / 60.0
        }

        var asleep = 0.0, inBed = 0.0, awake = 0.0, deep = 0.0, rem = 0.0
        var firstAsleepStart: Date?

        for s in samples {
            switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
            case .inBed:
                inBed += minutes(s)
            case .awake:
                awake += minutes(s)
            case .asleepDeep:
                deep += minutes(s); asleep += minutes(s)
                firstAsleepStart = min(firstAsleepStart ?? s.startDate, s.startDate)
            case .asleepREM:
                rem += minutes(s); asleep += minutes(s)
                firstAsleepStart = min(firstAsleepStart ?? s.startDate, s.startDate)
            case .asleepCore, .asleepUnspecified:
                asleep += minutes(s)
                firstAsleepStart = min(firstAsleepStart ?? s.startDate, s.startDate)
            default:
                break
            }
        }
        guard asleep > 0 else { return nil }

        // Sources that don't log explicit inBed: approximate as asleep + awake.
        if inBed < asleep { inBed = asleep + awake }

        var bedtimeHour = 0.0
        if let start = firstAsleepStart {
            let comps = calendar.dateComponents([.hour, .minute], from: start)
            bedtimeHour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
        }

        return SleepNight(asleepMinutes: asleep, inBedMinutes: inBed,
                          awakeMinutes: awake, deepMinutes: deep, remMinutes: rem,
                          bedtimeHour: bedtimeHour)
    }

    // MARK: - Hourly series for the "Day" chart range

    /// 24 hourly buckets for today (sum-type metrics: calories, steps).
    func fetchHourlySumToday(type: HKQuantityType, unit: HKUnit) async -> [Double] {
        guard isHealthKitAvailable else { return Array(repeating: 0, count: 24) }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: Date(),
                                                    options: .strictStartDate)
        var interval = DateComponents(); interval.hour = 1

        return await withCheckedContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: dayStart,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                var buckets = Array(repeating: 0.0, count: 24)
                results?.enumerateStatistics(from: dayStart, to: Date()) { stats, _ in
                    let hour = calendar.component(.hour, from: stats.startDate)
                    buckets[hour] = stats.sumQuantity()?.doubleValue(for: unit) ?? 0
                }
                cont.resume(returning: buckets)
            }
            Self.analyticsStore.execute(query)
        }
    }

    /// 24 hourly buckets for today (average-type metrics: heart rate).
    func fetchHourlyAverageToday(type: HKQuantityType, unit: HKUnit) async -> [Double] {
        guard isHealthKitAvailable else { return Array(repeating: 0, count: 24) }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: dayStart, end: Date(),
                                                    options: .strictStartDate)
        var interval = DateComponents(); interval.hour = 1

        return await withCheckedContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: dayStart,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                var buckets = Array(repeating: 0.0, count: 24)
                results?.enumerateStatistics(from: dayStart, to: Date()) { stats, _ in
                    let hour = calendar.component(.hour, from: stats.startDate)
                    buckets[hour] = stats.averageQuantity()?.doubleValue(for: unit) ?? 0
                }
                cont.resume(returning: buckets)
            }
            Self.analyticsStore.execute(query)
        }
    }
}
