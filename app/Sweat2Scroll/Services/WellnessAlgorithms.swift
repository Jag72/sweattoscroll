// Services/WellnessAlgorithms.swift
// Personal-baseline-aware scoring engine for Strain, Sleep, and Energy/Recovery.
//
// Design goals:
//   • Pure, static, deterministic functions — fully unit-testable, no HealthKit.
//   • Scores are relative to the USER'S OWN rolling baseline (mean ± SD over the
//     last 14–30 days), not fixed population constants — the same 55 ms HRV is
//     "great" for one person and "poor" for another.
//   • Graceful degradation: every score has a defined fallback when a sensor
//     stream is missing (no Watch, no sleep tracking, simulator).
//
// References:
//   Strain  — Banister TRIMP (exponential HR-reserve weighting; Banister 1991),
//             HRmax via Tanaka et al. 2001 (208 − 0.7·age), mapped to a 0–21
//             logarithmic scale (borg/WHOOP-style diminishing returns).
//   Sleep   — multi-component: duration vs need, efficiency, continuity,
//             schedule consistency, stage composition (NSF guidelines).
//   Energy  — z-score composite of lnHRV (+), RHR (−), respiratory rate (−)
//             vs personal baseline, blended with sleep score and yesterday's
//             training load (Plews et al. 2013 lnRMSSD methodology).

import Foundation

// MARK: - Inputs

/// One minute-bucketed heart-rate sample (from HKStatisticsCollectionQuery).
struct HRSample {
    let minuteOffset: Double   // minutes since window start
    let bpm: Double
}

/// A rolling personal baseline: mean and standard deviation of a metric.
struct MetricBaseline {
    let mean: Double
    let sd: Double
    let sampleCount: Int

    /// True when there's enough history to trust z-scores.
    var isReliable: Bool { sampleCount >= 5 && sd > 0 }

    /// Builds from a history window, ignoring missing (0) days.
    /// SD is floored at 5% of the mean so a hyper-consistent week doesn't turn
    /// tiny fluctuations into huge z-scores.
    static func from(_ history: [Double]) -> MetricBaseline {
        let nz = history.filter { $0 > 0 }
        guard !nz.isEmpty else { return MetricBaseline(mean: 0, sd: 0, sampleCount: 0) }
        let mean = nz.reduce(0, +) / Double(nz.count)
        let variance = nz.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(nz.count)
        let sd = max(sqrt(variance), mean * 0.05)
        return MetricBaseline(mean: mean, sd: sd, sampleCount: nz.count)
    }

    /// z-score of a value against this baseline, clamped to ±3.
    func z(_ value: Double) -> Double {
        guard isReliable, value > 0 else { return 0 }
        return min(3, max(-3, (value - mean) / sd))
    }
}

/// Detailed sleep night (all minutes). Any component may be 0 when the source
/// (e.g. iPhone-only tracking) doesn't provide it.
struct SleepNight {
    var asleepMinutes: Double      // total asleep (core+deep+REM or unspecified)
    var inBedMinutes: Double       // total in-bed window
    var awakeMinutes: Double       // awake-in-bed
    var deepMinutes: Double        // stage: deep
    var remMinutes: Double         // stage: REM
    var bedtimeHour: Double        // local clock hour user fell asleep (e.g. 23.5)
    var hasStages: Bool { deepMinutes > 0 || remMinutes > 0 }
}

// MARK: - Engine

enum WellnessAlgorithms {

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Strain (0–21)
    // ─────────────────────────────────────────────────────────────────────────

    /// Banister TRIMP from minute-bucketed HR samples.
    /// TRIMP = Σ Δt(min) · HRr · c1 · e^(c2 · HRr), HRr = (HR−RHR)/(HRmax−RHR).
    /// Sex-specific coefficients: male (0.64, 1.92), female (0.86, 1.67).
    static func trimp(samples: [HRSample],
                      restingHR: Double,
                      age: Int,
                      isFemale: Bool) -> Double {
        guard !samples.isEmpty else { return 0 }
        let rhr = restingHR > 30 ? restingHR : 60
        let hrMax = max(208 - 0.7 * Double(age), rhr + 20)   // Tanaka 2001
        let c1 = isFemale ? 0.86 : 0.64
        let c2 = isFemale ? 1.67 : 1.92

        var total = 0.0
        for (i, s) in samples.enumerated() {
            guard s.bpm > rhr else { continue }
            // Δt = gap to next sample, capped at 5 min so sparse data can't
            // multiply one elevated reading into a fake workout.
            let dt: Double
            if i + 1 < samples.count {
                dt = min(max(samples[i + 1].minuteOffset - s.minuteOffset, 0), 5)
            } else {
                dt = 1
            }
            let hrr = min((s.bpm - rhr) / (hrMax - rhr), 1.0)
            total += dt * hrr * c1 * exp(c2 * hrr)
        }
        return total
    }

    /// Maps raw TRIMP onto the familiar 0–21 strain scale with logarithmic
    /// diminishing returns. Calibration: TRIMP 60 (≈1 h moderate cardio) → ~10,
    /// TRIMP 250 (hard race day) → ~18, asymptote 21.
    static func strainScore(fromTRIMP trimp: Double) -> Double {
        guard trimp > 0 else { return 0 }
        // k=12 calibrates: TRIMP 60 → 10.0, TRIMP 155 (hard hour) → 14.7,
        // TRIMP 250 (race day) → 17.3, asymptote 21.
        let k = 12.0
        let maxTRIMP = 500.0
        let raw = 21.0 * log(1 + trimp / k) / log(1 + maxTRIMP / k)
        return min(raw, 21.0)
    }

    /// Fallback strain when no HR samples exist (no Watch): blends active
    /// energy and steps against the user's own 30-day maxima so a big day *for
    /// them* reads as high strain. Kept deliberately below 15 — without HR we
    /// can't verify true cardiovascular load.
    static func strainScoreFallback(activeKcal: Double,
                                    steps: Double,
                                    kcalBaseline: MetricBaseline,
                                    stepsBaseline: MetricBaseline) -> Double {
        let kcalRef  = max(kcalBaseline.mean * 1.8, 400)
        let stepsRef = max(stepsBaseline.mean * 1.8, 8000)
        let load = 0.65 * min(activeKcal / kcalRef, 1.3)
                 + 0.35 * min(steps / stepsRef, 1.3)
        guard load > 0 else { return 0 }
        // Power curve calibration: an average day (load ≈ 0.55) → ~7.4,
        // a huge day (load ≥ 1.3) → 15.
        return min(15.0 * pow(min(load / 1.3, 1.0), 0.85), 15.0)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Sleep score (0–100)
    // ─────────────────────────────────────────────────────────────────────────

    /// Multi-component sleep score.
    ///   duration    40% — vs 8 h need (partial credit follows a smooth curve)
    ///   efficiency  20% — asleep / in-bed (90%+ is ideal; NSF)
    ///   continuity  15% — awake minutes penalty (>30 min awake degrades)
    ///   consistency 15% — bedtime deviation vs recent median (±1 h grace)
    ///   stages      10% — deep 13–23% & REM 20–25% of sleep when available
    /// When a component's data is missing its weight is redistributed, so an
    /// iPhone-only user isn't structurally capped below 100.
    static func sleepScore(night: SleepNight,
                           recentBedtimes: [Double],
                           sleepNeedMinutes: Double = 480) -> (score: Double, components: SleepComponents) {
        guard night.asleepMinutes > 0 else {
            return (0, SleepComponents(duration: 0, efficiency: 0, continuity: 0, consistency: 0, stages: 0))
        }

        // Duration — smooth saturating curve; 8 h → 1.0, 6 h → 0.80, 4 h → 0.48.
        let ratio = night.asleepMinutes / max(sleepNeedMinutes, 60)
        let duration = min(pow(min(ratio, 1.15), 1.35), 1.0)

        // Efficiency — only when an in-bed window exists.
        var efficiency: Double? = nil
        if night.inBedMinutes > night.asleepMinutes * 0.5 {
            let eff = night.asleepMinutes / max(night.inBedMinutes, 1)
            // 0.90+ full credit, linear down to 0 at 0.60.
            efficiency = min(max((eff - 0.60) / 0.30, 0), 1)
        }

        // Continuity — ≤10 min awake full credit; 60+ min → 0.
        var continuity: Double? = nil
        if night.inBedMinutes > 0 {
            continuity = min(max(1 - (night.awakeMinutes - 10) / 50, 0), 1)
        }

        // Consistency — deviation of tonight's bedtime vs recent median.
        var consistency: Double? = nil
        if recentBedtimes.count >= 3, night.bedtimeHour > 0 {
            let median = recentBedtimes.sorted()[recentBedtimes.count / 2]
            var dev = abs(night.bedtimeHour - median)
            if dev > 12 { dev = 24 - dev }               // wrap around midnight
            consistency = min(max(1 - (dev - 1.0) / 2.0, 0), 1)  // ±1 h grace, 0 at 3 h
        }

        // Stage composition — deep 13–23%, REM 20–25% of asleep time.
        var stages: Double? = nil
        if night.hasStages {
            let deepPct = night.deepMinutes / night.asleepMinutes
            let remPct  = night.remMinutes  / night.asleepMinutes
            let deepScore = bandScore(deepPct, ideal: 0.13...0.23, floor: 0.05, ceil: 0.35)
            let remScore  = bandScore(remPct,  ideal: 0.20...0.25, floor: 0.08, ceil: 0.35)
            stages = (deepScore + remScore) / 2
        }

        // Weighted blend with redistribution of missing components.
        var weighted: [(value: Double, weight: Double)] = [(duration, 0.40)]
        if let e = efficiency  { weighted.append((e, 0.20)) }
        if let c = continuity  { weighted.append((c, 0.15)) }
        if let c = consistency { weighted.append((c, 0.15)) }
        if let s = stages      { weighted.append((s, 0.10)) }
        let totalWeight = weighted.reduce(0) { $0 + $1.weight }
        let score = weighted.reduce(0) { $0 + $1.value * ($1.weight / totalWeight) } * 100

        let comps = SleepComponents(duration: duration,
                                    efficiency: efficiency ?? duration,
                                    continuity: continuity ?? duration,
                                    consistency: consistency ?? duration,
                                    stages: stages ?? duration)
        return (min(max(score, 0), 100), comps)
    }

    struct SleepComponents {
        let duration: Double      // 0–1
        let efficiency: Double
        let continuity: Double
        let consistency: Double
        let stages: Double
    }

    /// 1.0 inside `ideal`, tapering linearly to 0 at `floor` / `ceil`.
    private static func bandScore(_ v: Double, ideal: ClosedRange<Double>,
                                  floor: Double, ceil: Double) -> Double {
        if ideal.contains(v) { return 1 }
        if v < ideal.lowerBound {
            return min(max((v - floor) / (ideal.lowerBound - floor), 0), 1)
        }
        return min(max((ceil - v) / (ceil - ideal.upperBound), 0), 1)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Energy / Recovery (0–100)
    // ─────────────────────────────────────────────────────────────────────────

    /// Baseline-relative readiness score.
    ///   physiology 55% — 0.55·z(lnHRV) − 0.33·z(RHR) − 0.12·z(resp), sigmoid-mapped
    ///   sleep      30% — last night's sleep score
    ///   load       15% — inverse of yesterday's strain (hard day → lower energy)
    /// Falls back to the activity-ring composite when HRV/RHR baselines aren't
    /// reliable yet (first days of use / no Watch).
    static func energyScore(hrvToday: Double,
                            rhrToday: Double,
                            respToday: Double,
                            hrvBaseline: MetricBaseline,
                            rhrBaseline: MetricBaseline,
                            respBaseline: MetricBaseline,
                            sleepScore: Double,
                            yesterdayStrain: Double,
                            activityRingFallback: Double) -> Double {
        // lnRMSSD-style transform stabilizes HRV distribution (Plews 2013).
        let lnBaseline = MetricBaseline(
            mean: hrvBaseline.mean > 0 ? log(hrvBaseline.mean) : 0,
            sd: hrvBaseline.mean > 0 ? max(hrvBaseline.sd / hrvBaseline.mean, 0.03) : 0,
            sampleCount: hrvBaseline.sampleCount
        )

        guard hrvBaseline.isReliable || rhrBaseline.isReliable else {
            // Not enough biometric history — blend rings with sleep if present.
            if sleepScore > 0 {
                return min(max(0.6 * activityRingFallback + 0.4 * sleepScore, 0), 100)
            }
            return activityRingFallback
        }

        let zHRV  = hrvToday > 0 ? lnBaseline.z(log(hrvToday)) : 0
        let zRHR  = rhrBaseline.z(rhrToday)
        let zResp = respBaseline.z(respToday)

        let physioComposite = 0.55 * zHRV - 0.33 * zRHR - 0.12 * zResp   // ≈ −1…+1 typical
        // Sigmoid → 0–100 centered at 50, ±1 composite ≈ 27/73.
        let physio = 100 / (1 + exp(-1.0 * physioComposite))

        let sleepPart = sleepScore > 0 ? sleepScore : physio   // redistribute if absent
        let loadPart  = max(0, 100 - (yesterdayStrain / 21.0) * 100)

        let score = 0.55 * physio + 0.30 * sleepPart + 0.15 * loadPart
        return min(max(score, 0), 100)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Insights (auto-generated comparison text)
    // ─────────────────────────────────────────────────────────────────────────

    struct Insight: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
        let isPositive: Bool
    }

    /// Human-readable, baseline-relative statements for the analytics page.
    static func insights(hrvToday: Double, hrvBaseline: MetricBaseline,
                         rhrToday: Double, rhrBaseline: MetricBaseline,
                         sleepMinutesLast: Double, sleepBaseline: MetricBaseline,
                         stepsThisWeekAvg: Double, stepsLastWeekAvg: Double,
                         kcalThisWeekAvg: Double, kcalLastWeekAvg: Double) -> [Insight] {
        var out: [Insight] = []

        if hrvBaseline.isReliable, hrvToday > 0 {
            let pct = (hrvToday - hrvBaseline.mean) / hrvBaseline.mean * 100
            if abs(pct) >= 5 {
                out.append(Insight(
                    icon: "waveform.path.ecg",
                    text: String(format: "HRV is %.0f%% %@ your 30-day baseline (%.0f ms) — %@.",
                                 abs(pct), pct >= 0 ? "above" : "below", hrvBaseline.mean,
                                 pct >= 0 ? "your body is recovering well" : "consider an easier day"),
                    isPositive: pct >= 0))
            }
        }
        if rhrBaseline.isReliable, rhrToday > 0 {
            let delta = rhrToday - rhrBaseline.mean
            if abs(delta) >= 3 {
                out.append(Insight(
                    icon: "heart.fill",
                    text: String(format: "Resting HR is %.0f bpm %@ your usual %.0f — %@.",
                                 abs(delta), delta <= 0 ? "below" : "above", rhrBaseline.mean,
                                 delta <= 0 ? "a good recovery signal" : "often a sign of fatigue or stress"),
                    isPositive: delta <= 0))
            }
        }
        if sleepBaseline.isReliable, sleepMinutesLast > 0 {
            let deltaMin = sleepMinutesLast - sleepBaseline.mean
            if abs(deltaMin) >= 30 {
                out.append(Insight(
                    icon: "moon.fill",
                    text: String(format: "You slept %dh %02dm — %.0f min %@ your average night.",
                                 Int(sleepMinutesLast) / 60, Int(sleepMinutesLast) % 60,
                                 abs(deltaMin), deltaMin >= 0 ? "more than" : "less than"),
                    isPositive: deltaMin >= 0))
            }
        }
        if stepsLastWeekAvg > 0 {
            let pct = (stepsThisWeekAvg - stepsLastWeekAvg) / stepsLastWeekAvg * 100
            if abs(pct) >= 10 {
                out.append(Insight(
                    icon: "figure.walk",
                    text: String(format: "Daily steps are %@ %.0f%% week-over-week (%.0f → %.0f avg).",
                                 pct >= 0 ? "up" : "down", abs(pct), stepsLastWeekAvg, stepsThisWeekAvg),
                    isPositive: pct >= 0))
            }
        }
        if kcalLastWeekAvg > 0 {
            let pct = (kcalThisWeekAvg - kcalLastWeekAvg) / kcalLastWeekAvg * 100
            if abs(pct) >= 10 {
                out.append(Insight(
                    icon: "flame.fill",
                    text: String(format: "Active burn is %@ %.0f%% vs last week (avg %.0f kcal/day).",
                                 pct >= 0 ? "up" : "down", abs(pct), kcalThisWeekAvg),
                    isPositive: pct >= 0))
            }
        }
        return out
    }
}
