// Services/CalorieEngine.swift
// Computes CDC-recommended active calorie goals.
// Uses Mifflin-St Jeor (adults 19+) and IOM EER (under 18).
// Enforces hard safety caps per age cohort.
// MET-based active calorie formula for final goal derivation.

import Foundation

struct CalorieEngine {

    // MARK: - Safety Caps (non-negotiable, enforced at architecture level)
    static let pediatricHardCap: Double    = 500    // Under 13
    static let adolescentHardCap: Double   = 800    // 13–18
    static let adultHardCap: Double        = 1000   // 19+

    // MARK: - CDC Physical Activity Baseline
    // CDC recommends 150 min/week of moderate activity for adults = 21.4 min/day
    static let cdcDailyMinutes: Double     = 21.4
    static let moderateMET: Double         = 4.3    // Walking 3.5 mph MET value

    // MARK: - IOM Physical Activity Coefficients (Pediatric/Adolescent)
    static let paLowActiveBoys: Double     = 1.13
    static let paLowActiveGirls: Double    = 1.16

    // MARK: - Main Entry Point
    /// Computes the recommended active calorie goal for a given user profile.
    /// Returns a value clamped to the age-appropriate hard cap.
    static func computeGoal(for profile: UserProfile) -> ActivityGoal {
        let rmr = computeRMR(for: profile)
        let rawActiveCalories = computeActiveCalories(profile: profile, rmr: rmr)
        let cap = hardCap(for: profile.ageCohort)
        let clamped = min(rawActiveCalories, cap)

        return ActivityGoal(
            currency: profile.goalCurrency,
            recommendedTarget: clamped,
            agreedTarget: clamped,
            hardCap: cap
        )
    }

    // MARK: - Resting Metabolic Rate
    /// Adult: Mifflin-St Jeor equation (most accurate within 10% for modern populations)
    /// Pediatric/Adolescent: IOM EER equation
    static func computeRMR(for profile: UserProfile) -> Double {
        switch profile.ageCohort {

        case .adult:
            // Mifflin-St Jeor
            let base = (10 * profile.weightKg) + (6.25 * profile.heightCm) - (5 * Double(profile.ageYears))
            switch profile.biologicalSex {
            case .male:   return base + 5
            case .female: return base - 161
            case .other:  return base - 78  // Average of both
            }

        case .adolescent, .pediatric:
            let heightM = profile.heightCm / 100
            switch profile.biologicalSex {
            case .male:
                // IOM EER — Boys 3–18
                let pa = paLowActiveBoys
                return 88.5 - (61.9 * Double(profile.ageYears))
                     + pa * ((26.7 * profile.weightKg) + (903 * heightM)) + 25

            case .female, .other:
                // IOM EER — Girls 3–18
                let pa = paLowActiveGirls
                return 135.3 - (30.8 * Double(profile.ageYears))
                     + pa * ((10.0 * profile.weightKg) + (934 * heightM)) + 25
            }
        }
    }

    // MARK: - Active Calorie Goal via MET Formula
    /// Calories_active = (MET × 3.5 × weight_kg / 200) × duration_minutes
    static func computeActiveCalories(profile: UserProfile, rmr: Double) -> Double {
        switch profile.ageCohort {
        case .adult:
            return (moderateMET * 3.5 * profile.weightKg / 200) * cdcDailyMinutes

        case .adolescent:
            // 60 min/day recommended — use upper bound of 400 kcal range
            return (moderateMET * 3.5 * profile.weightKg / 200) * 40

        case .pediatric:
            // 60 min active play — use upper bound of 300 kcal range
            return (moderateMET * 3.5 * profile.weightKg / 200) * 30
        }
    }

    // MARK: - Steps Equivalent
    /// Converts an active calorie goal to approximate step count equivalent.
    /// Guards against `profile.weightKg == 0` (which would make `kcalPerStep`
    /// zero and crash on `Int(calories / 0)` → infinity) by falling back to
    /// the 70 kg reference weight. Returns 0 for non-positive calorie goals.
    static func stepsEquivalent(for calories: Double, profile: UserProfile) -> Int {
        guard calories > 0 else { return 0 }
        let referenceWeight: Double = 70
        let weight = profile.weightKg > 0 ? profile.weightKg : referenceWeight
        // ~0.04 kcal per step average (varies by weight, stride)
        let kcalPerStep = 0.04 * (weight / referenceWeight)
        guard kcalPerStep > 0 else { return 0 }
        return Int(calories / kcalPerStep)
    }

    // MARK: - Hard Caps
    static func hardCap(for cohort: AgeCohort) -> Double {
        switch cohort {
        case .pediatric:   return pediatricHardCap
        case .adolescent:  return adolescentHardCap
        case .adult:       return adultHardCap
        }
    }

    // MARK: - Validation
    /// Validates that a proposed target is within safe bounds
    static func validate(target: Double, for profile: UserProfile) -> (isValid: Bool, reason: String?) {
        let cap = hardCap(for: profile.ageCohort)
        if target > cap {
            return (false, "Exceeds the safe daily limit of \(Int(cap)) kcal for your age group.")
        }
        if target < 50 {
            return (false, "Goal must be at least 50 kcal to be meaningful.")
        }
        return (true, nil)
    }
}
