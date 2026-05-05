// Models/UserProfile.swift
// Stores biometric data read from HealthKit.
// Used by CalorieEngine to compute CDC-recommended active calorie goals.

import Foundation

enum BiologicalSex: String, Codable {
    case male, female, other
}

enum AgeCohort {
    case pediatric      // Under 13  — IOM EER, cap 500 kcal
    case adolescent     // 13–18     — IOM EER, cap 800 kcal
    case adult          // 19+       — Mifflin-St Jeor, cap 1000 kcal
}

struct UserProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()

    // From HealthKit
    var weightKg: Double        // HKQuantityTypeIdentifier.bodyMass
    var heightCm: Double        // HKQuantityTypeIdentifier.height
    var ageYears: Int           // Derived from HKCharacteristicTypeIdentifier.dateOfBirth
    var biologicalSex: BiologicalSex  // HKCharacteristicTypeIdentifier.biologicalSex

    // Derived
    var ageCohort: AgeCohort {
        switch ageYears {
        case ..<13:  return .pediatric
        case 13...18: return .adolescent
        default:      return .adult
        }
    }

    // Display name for pairing and governance contract
    var displayName: String = ""

    // Goal currency chosen by Controller during onboarding
    var goalCurrency: GoalCurrency

    static let placeholder = UserProfile(
        weightKg: 70,
        heightCm: 175,
        ageYears: 30,
        biologicalSex: .male,
        goalCurrency: .activeCalories
    )
}
