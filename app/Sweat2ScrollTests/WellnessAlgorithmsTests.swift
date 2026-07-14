// Sweat2ScrollTests/WellnessAlgorithmsTests.swift
// Pins the scoring contracts of the WellnessAlgorithms engine.

import XCTest
@testable import Sweat2Scroll

final class WellnessAlgorithmsTests: XCTestCase {

    // MARK: - Baseline

    func testBaselineIgnoresMissingDays() {
        let base = MetricBaseline.from([0, 50, 0, 60, 55, 0, 58])
        XCTAssertEqual(base.mean, (50 + 60 + 55 + 58) / 4, accuracy: 0.01)
        XCTAssertEqual(base.sampleCount, 4)
    }

    func testBaselineUnreliableWithFewSamples() {
        XCTAssertFalse(MetricBaseline.from([50, 55]).isReliable)
        XCTAssertTrue(MetricBaseline.from([50, 55, 60, 52, 58]).isReliable)
    }

    func testZScoreClampedToPlusMinus3() {
        let base = MetricBaseline.from([50, 51, 49, 50, 50, 51, 49])
        XCTAssertEqual(base.z(500), 3, accuracy: 0.001)
        XCTAssertEqual(base.z(1), -3, accuracy: 0.001)
    }

    // MARK: - Strain / TRIMP

    func testTrimpZeroWithoutElevatedHR() {
        let samples = (0..<60).map { HRSample(minuteOffset: Double($0), bpm: 55) }
        XCTAssertEqual(WellnessAlgorithms.trimp(samples: samples, restingHR: 60, age: 30, isFemale: false), 0)
    }

    func testTrimpIncreasesWithIntensity() {
        let easy = (0..<60).map { HRSample(minuteOffset: Double($0), bpm: 110) }
        let hard = (0..<60).map { HRSample(minuteOffset: Double($0), bpm: 165) }
        let tEasy = WellnessAlgorithms.trimp(samples: easy, restingHR: 60, age: 30, isFemale: false)
        let tHard = WellnessAlgorithms.trimp(samples: hard, restingHR: 60, age: 30, isFemale: false)
        XCTAssertGreaterThan(tHard, tEasy * 2, "exponential HR-reserve weighting expected")
    }

    func testTrimpCapsSparseSampleGaps() {
        // One elevated reading followed by a 4-hour gap must not count as 4 h of work.
        let sparse = [HRSample(minuteOffset: 0, bpm: 150),
                      HRSample(minuteOffset: 240, bpm: 150)]
        let t = WellnessAlgorithms.trimp(samples: sparse, restingHR: 60, age: 30, isFemale: false)
        let dense = (0..<6).map { HRSample(minuteOffset: Double($0), bpm: 150) }
        let tDense = WellnessAlgorithms.trimp(samples: dense, restingHR: 60, age: 30, isFemale: false)
        XCTAssertEqual(t, tDense, accuracy: tDense * 0.2, "gap should be capped to ~5 min")
    }

    func testStrainScaleCalibration() {
        XCTAssertEqual(WellnessAlgorithms.strainScore(fromTRIMP: 0), 0)
        let moderate = WellnessAlgorithms.strainScore(fromTRIMP: 60)
        XCTAssertTrue((8...13).contains(moderate), "1 h moderate cardio should land ~10, got \(moderate)")
        XCTAssertLessThanOrEqual(WellnessAlgorithms.strainScore(fromTRIMP: 10_000), 21)
    }

    func testStrainFallbackBounded() {
        let base = MetricBaseline.from([300, 320, 280, 310, 305, 290, 315])
        let sBase = MetricBaseline.from([8000, 9000, 7500, 8200, 8800, 7900, 8500])
        let s = WellnessAlgorithms.strainScoreFallback(activeKcal: 5000, steps: 60000,
                                                       kcalBaseline: base, stepsBaseline: sBase)
        XCTAssertLessThanOrEqual(s, 15, "fallback strain must stay ≤15 without HR proof")
        XCTAssertEqual(WellnessAlgorithms.strainScoreFallback(activeKcal: 0, steps: 0,
                                                              kcalBaseline: base, stepsBaseline: sBase),
                       0, accuracy: 0.01)
    }

    // MARK: - Sleep

    private func night(asleep: Double, inBed: Double? = nil, awake: Double = 15,
                       deep: Double = 0, rem: Double = 0, bedtime: Double = 23) -> SleepNight {
        SleepNight(asleepMinutes: asleep, inBedMinutes: inBed ?? (asleep + awake),
                   awakeMinutes: awake, deepMinutes: deep, remMinutes: rem, bedtimeHour: bedtime)
    }

    func testPerfectNightScoresHigh() {
        let n = night(asleep: 480, awake: 5, deep: 480 * 0.18, rem: 480 * 0.22)
        let (score, _) = WellnessAlgorithms.sleepScore(night: n, recentBedtimes: [23, 23.2, 22.8, 23.1])
        XCTAssertGreaterThan(score, 90)
    }

    func testShortNightScoresLow() {
        let n = night(asleep: 240, awake: 40)
        let (score, _) = WellnessAlgorithms.sleepScore(night: n, recentBedtimes: [23, 23, 23])
        XCTAssertLessThan(score, 65)
    }

    func testErraticBedtimePenalized() {
        let steady = WellnessAlgorithms.sleepScore(night: night(asleep: 420, bedtime: 23),
                                                   recentBedtimes: [23, 23.1, 22.9, 23]).score
        let erratic = WellnessAlgorithms.sleepScore(night: night(asleep: 420, bedtime: 3.5),
                                                    recentBedtimes: [23, 23.1, 22.9, 23]).score
        XCTAssertGreaterThan(steady, erratic)
    }

    func testBedtimeWrapAroundMidnight() {
        // 00:30 vs a 23:30 median is a 1 h deviation, not 23 h.
        let (score, comps) = WellnessAlgorithms.sleepScore(
            night: night(asleep: 450, bedtime: 0.5),
            recentBedtimes: [23.5, 23.4, 23.6])
        XCTAssertGreaterThan(comps.consistency, 0.9, "wrap-around should treat 0:30 as close to 23:30")
        XCTAssertGreaterThan(score, 80)
    }

    func testMissingComponentsRedistributed() {
        // iPhone-only: no stages, no meaningful in-bed window — can still reach high scores.
        let n = SleepNight(asleepMinutes: 470, inBedMinutes: 0, awakeMinutes: 0,
                           deepMinutes: 0, remMinutes: 0, bedtimeHour: 0)
        let (score, _) = WellnessAlgorithms.sleepScore(night: n, recentBedtimes: [])
        XCTAssertGreaterThan(score, 85)
    }

    // MARK: - Energy / Recovery

    private let goodHRVBase  = MetricBaseline.from([55, 58, 52, 60, 56, 54, 57, 59, 55, 56])
    private let goodRHRBase  = MetricBaseline.from([52, 53, 51, 52, 54, 52, 51, 53, 52, 52])
    private let goodRespBase = MetricBaseline.from([15, 15.2, 14.8, 15.1, 15, 14.9, 15.3])

    func testEnergyHighWhenAboveBaseline() {
        let score = WellnessAlgorithms.energyScore(
            hrvToday: 68, rhrToday: 48, respToday: 14.5,
            hrvBaseline: goodHRVBase, rhrBaseline: goodRHRBase, respBaseline: goodRespBase,
            sleepScore: 90, yesterdayStrain: 8, activityRingFallback: 40)
        XCTAssertGreaterThan(score, 70)
    }

    func testEnergyLowWhenSuppressed() {
        let score = WellnessAlgorithms.energyScore(
            hrvToday: 38, rhrToday: 62, respToday: 17.5,
            hrvBaseline: goodHRVBase, rhrBaseline: goodRHRBase, respBaseline: goodRespBase,
            sleepScore: 45, yesterdayStrain: 19, activityRingFallback: 40)
        XCTAssertLessThan(score, 45)
    }

    func testEnergyFallsBackToRingsWithoutBaselines() {
        let empty = MetricBaseline.from([])
        let score = WellnessAlgorithms.energyScore(
            hrvToday: 0, rhrToday: 0, respToday: 0,
            hrvBaseline: empty, rhrBaseline: empty, respBaseline: empty,
            sleepScore: 0, yesterdayStrain: 0, activityRingFallback: 62)
        XCTAssertEqual(score, 62, accuracy: 0.01)
    }

    func testEnergyAlwaysClamped() {
        let score = WellnessAlgorithms.energyScore(
            hrvToday: 500, rhrToday: 20, respToday: 5,
            hrvBaseline: goodHRVBase, rhrBaseline: goodRHRBase, respBaseline: goodRespBase,
            sleepScore: 100, yesterdayStrain: 0, activityRingFallback: 100)
        XCTAssertLessThanOrEqual(score, 100)
        XCTAssertGreaterThanOrEqual(score, 0)
    }

    // MARK: - Insights

    func testInsightsGeneratedForMeaningfulDeltas() {
        let insights = WellnessAlgorithms.insights(
            hrvToday: 65, hrvBaseline: goodHRVBase,
            rhrToday: 58, rhrBaseline: goodRHRBase,
            sleepMinutesLast: 380, sleepBaseline: MetricBaseline.from([430, 440, 450, 435, 445]),
            stepsThisWeekAvg: 9000, stepsLastWeekAvg: 7000,
            kcalThisWeekAvg: 350, kcalLastWeekAvg: 300)
        XCTAssertGreaterThanOrEqual(insights.count, 3)
    }

    func testNoInsightsWithoutData() {
        let empty = MetricBaseline.from([])
        let insights = WellnessAlgorithms.insights(
            hrvToday: 0, hrvBaseline: empty, rhrToday: 0, rhrBaseline: empty,
            sleepMinutesLast: 0, sleepBaseline: empty,
            stepsThisWeekAvg: 0, stepsLastWeekAvg: 0,
            kcalThisWeekAvg: 0, kcalLastWeekAvg: 0)
        XCTAssertTrue(insights.isEmpty)
    }
}
