// UserBodyProfileStorage.swift
// Persistent height / weight / age / sex edited in-app or prefilled from Health.
// Merged with Apple Health in `HealthKitService.mergeUserProfileFromSources()`.

import Foundation

enum UserBodyProfileStorage {

    private static let heightCmKey = "userBody.heightCm"
    private static let weightKgKey = "userBody.weightKg"
    private static let ageYearsKey = "userBody.ageYears"
    private static let biologicalSexKey = "userBody.biologicalSexRaw"

    /// Legacy PRD onboarding keys — migrated on read when unified keys are absent.
    private static let legacyHeightKey = "prdHeightCm"
    private static let legacyWeightKey = "prdWeightKg"
    private static let legacyAgeKey = "prdAgeYears"

    struct Saved {
        var heightCm: Double?
        var weightKg: Double?
        var ageYears: Int?
        var biologicalSex: BiologicalSex?
    }

    static func load() -> Saved {
        let d = UserDefaults.standard

        let height: Double? = {
            if d.object(forKey: heightCmKey) != nil { return d.double(forKey: heightCmKey) }
            if d.object(forKey: legacyHeightKey) != nil { return d.double(forKey: legacyHeightKey) }
            return nil
        }()

        let weight: Double? = {
            if d.object(forKey: weightKgKey) != nil { return d.double(forKey: weightKgKey) }
            if d.object(forKey: legacyWeightKey) != nil { return d.double(forKey: legacyWeightKey) }
            return nil
        }()

        let age: Int? = {
            if let v = d.object(forKey: ageYearsKey) as? Int { return v }
            if let v = d.object(forKey: legacyAgeKey) as? Int { return v }
            return nil
        }()

        let sex: BiologicalSex? = {
            guard let raw = d.string(forKey: biologicalSexKey),
                  let s = BiologicalSex(rawValue: raw) else { return nil }
            return s
        }()

        return Saved(heightCm: height, weightKg: weight, ageYears: age, biologicalSex: sex)
    }

    /// Saves unified keys and mirrors legacy PRD keys so older onboarding code keeps working.
    static func save(heightCm: Double, weightKg: Double, ageYears: Int, biologicalSex: BiologicalSex) {
        let d = UserDefaults.standard
        d.set(heightCm, forKey: heightCmKey)
        d.set(weightKg, forKey: weightKgKey)
        d.set(ageYears, forKey: ageYearsKey)
        d.set(biologicalSex.rawValue, forKey: biologicalSexKey)
        // Legacy mirrors (used by OnboardingCompleteView / CloudKit payloads)
        d.set(heightCm, forKey: legacyHeightKey)
        d.set(weightKg, forKey: legacyWeightKey)
        d.set(ageYears, forKey: legacyAgeKey)
    }
}
