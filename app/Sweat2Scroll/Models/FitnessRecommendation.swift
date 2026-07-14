// Models/FitnessRecommendation.swift
// Shared, unit-aware helpers for BMI classification, weight units, and a
// BMI-informed daily active-calorie-burn recommendation. Used by onboarding
// (manual entry + calorie goal) and available for Profile/dashboard later.

import Foundation

// MARK: - Weight units

enum WeightUnit: String, CaseIterable, Codable {
    case kg
    case lb

    var label: String { self == .kg ? "kg" : "lb" }

    /// Sensible input bounds for a stepper/validation in this unit.
    var range: ClosedRange<Double> {
        self == .kg ? 30...250 : 66...550
    }

    private static let kgPerLb = 0.45359237

    /// Convert a value in this unit to kilograms (the app's canonical unit).
    func toKilograms(_ value: Double) -> Double {
        self == .kg ? value : value * Self.kgPerLb
    }

    /// Convert kilograms into a value expressed in this unit.
    func fromKilograms(_ kg: Double) -> Double {
        self == .kg ? kg : kg / Self.kgPerLb
    }
}

/// Small persisted preference so the chosen weight unit stays consistent.
enum WeightUnitPreference {
    private static let key = "weightUnitPreference"

    static func load() -> WeightUnit {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let unit = WeightUnit(rawValue: raw) else { return .kg }
        return unit
    }

    static func save(_ unit: WeightUnit) {
        UserDefaults.standard.set(unit.rawValue, forKey: key)
    }
}

// MARK: - BMI classification

enum BMICategory: String {
    case underweight = "Underweight"
    case normal      = "Normal"
    case overweight  = "Overweight"
    case obese       = "Obese"

    static func from(bmi: Double) -> BMICategory {
        switch bmi {
        case ..<18.5:   return .underweight
        case 18.5..<25: return .normal
        case 25..<30:   return .overweight
        default:        return .obese
        }
    }

    /// One-line, encouraging guidance shown alongside the recommendation.
    var guidance: String {
        switch self {
        case .underweight:
            return "You're below the healthy range — keep movement gentle and steady."
        case .normal:
            return "You're in the healthy range — this keeps you fit and consistent."
        case .overweight:
            return "A daily burn helps you trend toward your healthy weight range."
        case .obese:
            return "Small daily wins compound — start steady and build over time."
        }
    }
}

// MARK: - Calorie-burn recommendation

enum CalorieRecommendation {
    /// Recommended daily **active-calorie burn** target (kcal) to build fitness.
    ///
    /// "Active calories" is the energy burned through movement — the currency
    /// Sweat2Scroll gates on — not total daily expenditure (TDEE). The target
    /// scales with BMI category (higher BMI → larger, still-realistic burn to
    /// support a healthy trend) and nudges slightly with body weight.
    /// Result is rounded to the nearest 25 kcal and clamped to a safe range.
    static func dailyActiveBurn(bmi: Double?, weightKg: Double?) -> Double {
        guard let bmi else { return 400 }

        let base: Double
        switch BMICategory.from(bmi: bmi) {
        case .underweight: base = 250
        case .normal:      base = 400
        case .overweight:  base = 500
        case .obese:       base = 600
        }

        // Heavier users burn more per unit of activity and generally benefit
        // from a somewhat larger target; lighter users a bit less. Reference
        // 75 kg, ~1 kcal per kg of deviation, capped so it stays realistic.
        let weightAdjustment = max(-100, min(150, ((weightKg ?? 75) - 75) * 1.0))

        let target = base + weightAdjustment
        let rounded = (target / 25).rounded() * 25
        return max(150, min(900, rounded))
    }
}
