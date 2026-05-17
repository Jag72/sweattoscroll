// CalorieEngineExtraTests.swift
// Adds coverage beyond the existing 3 tests in `CalorieEngineTests.swift`:
//   - Age-cohort boundaries (12/13 + 18/19) that switch RMR formula.
//   - `biologicalSex == .other` branch (avg-of-male-and-female fallback).
//   - `validate(target:for:)` matrix.
//   - `stepsEquivalent` with `weightKg == 0` (regression: previously crashed
//     via Int(.infinity)) and with non-positive calorie input.
//
// Pins the safety caps from CLAUDE.md as load-bearing constants — flipping
// any of them silently would alter the goal a real user receives.

import XCTest
@testable import Sweat2Scroll

final class CalorieEngineExtraTests: XCTestCase {

    private func profile(age: Int,
                         weight: Double = 70,
                         height: Double = 175,
                         sex: BiologicalSex = .male) -> UserProfile {
        var p = UserProfile.placeholder
        p.ageYears = age
        p.weightKg = weight
        p.heightCm = height
        p.biologicalSex = sex
        return p
    }

    // MARK: - Age-cohort boundaries

    func testAgeCohort_underThirteenIsPediatric() {
        XCTAssertEqual(profile(age: 12).ageCohort, .pediatric)
        XCTAssertEqual(profile(age: 5).ageCohort, .pediatric)
    }

    func testAgeCohort_thirteenThroughEighteenIsAdolescent() {
        XCTAssertEqual(profile(age: 13).ageCohort, .adolescent)
        XCTAssertEqual(profile(age: 18).ageCohort, .adolescent)
    }

    func testAgeCohort_nineteenAndOverIsAdult() {
        XCTAssertEqual(profile(age: 19).ageCohort, .adult)
        XCTAssertEqual(profile(age: 80).ageCohort, .adult)
    }

    // MARK: - Hard caps pinned

    func testHardCaps_pinnedValues() {
        // These constants are referenced by name in CLAUDE.md. Flipping one
        // silently would change the goal real users receive — the test plan
        // calls them out as safety boundaries.
        XCTAssertEqual(CalorieEngine.pediatricHardCap, 500)
        XCTAssertEqual(CalorieEngine.adolescentHardCap, 800)
        XCTAssertEqual(CalorieEngine.adultHardCap, 1000)
    }

    func testHardCap_perCohort() {
        XCTAssertEqual(CalorieEngine.hardCap(for: .pediatric), 500)
        XCTAssertEqual(CalorieEngine.hardCap(for: .adolescent), 800)
        XCTAssertEqual(CalorieEngine.hardCap(for: .adult), 1000)
    }

    // MARK: - computeGoal — boundary cohort transitions

    func testComputeGoal_pediatric_clampedAtPediatricCap() {
        let p = profile(age: 10, weight: 80, height: 150, sex: .male)
        let goal = CalorieEngine.computeGoal(for: p)
        XCTAssertEqual(goal.hardCap, CalorieEngine.pediatricHardCap)
        XCTAssertLessThanOrEqual(goal.agreedTarget, CalorieEngine.pediatricHardCap)
    }

    func testComputeGoal_adolescentBoundary_thirteen() {
        let p = profile(age: 13, weight: 60, height: 165)
        let goal = CalorieEngine.computeGoal(for: p)
        XCTAssertEqual(goal.hardCap, CalorieEngine.adolescentHardCap)
    }

    func testComputeGoal_adultBoundary_nineteen() {
        let p = profile(age: 19, weight: 70, height: 175)
        let goal = CalorieEngine.computeGoal(for: p)
        XCTAssertEqual(goal.hardCap, CalorieEngine.adultHardCap)
    }

    // MARK: - RMR — biologicalSex .other branch

    func testComputeRMR_adult_otherSex_isAverageOfMaleAndFemale() {
        let male = CalorieEngine.computeRMR(for: profile(age: 30, sex: .male))
        let female = CalorieEngine.computeRMR(for: profile(age: 30, sex: .female))
        let other = CalorieEngine.computeRMR(for: profile(age: 30, sex: .other))

        // Male = base + 5; female = base - 161; other = base - 78.
        // → other should sit between female and male, ~midpoint of the
        // (-161, +5) range. We assert the strict ordering rather than the
        // exact midpoint to stay robust to formula tweaks.
        XCTAssertGreaterThan(other, female)
        XCTAssertLessThan(other, male)
    }

    func testComputeRMR_pediatric_otherSex_usesGirlsFormula() {
        // Implementation choice: `.other` falls into the girls branch for
        // pediatric/adolescent. Pin so accidental refactors don't switch
        // it silently.
        let girls = CalorieEngine.computeRMR(for: profile(age: 10, sex: .female))
        let other = CalorieEngine.computeRMR(for: profile(age: 10, sex: .other))
        XCTAssertEqual(other, girls, accuracy: 0.001)
    }

    // MARK: - validate(target:for:)

    func testValidate_targetTooHigh() {
        let p = profile(age: 30)
        let r = CalorieEngine.validate(target: 1500, for: p)
        XCTAssertFalse(r.isValid)
        XCTAssertNotNil(r.reason)
        XCTAssertTrue(r.reason!.contains("1000"),
                      "Reason should reference the adult cap (1000): \(r.reason!)")
    }

    func testValidate_targetTooLow() {
        let p = profile(age: 30)
        let r = CalorieEngine.validate(target: 25, for: p)
        XCTAssertFalse(r.isValid)
        XCTAssertNotNil(r.reason)
    }

    func testValidate_targetWithinRange() {
        let p = profile(age: 30)
        let r = CalorieEngine.validate(target: 400, for: p)
        XCTAssertTrue(r.isValid)
        XCTAssertNil(r.reason)
    }

    func testValidate_pediatricUsesPediatricCap() {
        let p = profile(age: 10)
        let r = CalorieEngine.validate(target: 700, for: p)  // above pediatric cap (500)
        XCTAssertFalse(r.isValid)
        XCTAssertTrue(r.reason!.contains("500"))
    }

    // MARK: - stepsEquivalent regressions

    func testStepsEquivalent_zeroWeight_doesNotCrash() {
        // Regression: previously `Int(calories / 0)` trapped via Int(.infinity).
        // Guard now substitutes the 70 kg reference weight.
        var p = UserProfile.placeholder
        p.weightKg = 0
        let steps = CalorieEngine.stepsEquivalent(for: 400, profile: p)
        XCTAssertGreaterThan(steps, 0,
                             "Zero-weight profile must not crash and must produce a usable step estimate")
    }

    func testStepsEquivalent_zeroCalories_returnsZero() {
        XCTAssertEqual(CalorieEngine.stepsEquivalent(for: 0, profile: .placeholder), 0)
    }

    func testStepsEquivalent_negativeCalories_returnsZero() {
        XCTAssertEqual(CalorieEngine.stepsEquivalent(for: -100, profile: .placeholder), 0)
    }

    func testStepsEquivalent_referenceWeight_isAround10kStepsForGoal() {
        // 70 kg reference: kcalPerStep = 0.04 → 400 kcal / 0.04 = 10,000 steps.
        // Loose bounds because weight scaling kicks in at non-reference weights.
        var p = UserProfile.placeholder
        p.weightKg = 70
        let steps = CalorieEngine.stepsEquivalent(for: 400, profile: p)
        XCTAssertEqual(steps, 10_000)
    }

    func testStepsEquivalent_lighterPersonNeedsMoreSteps() {
        var heavy = UserProfile.placeholder
        heavy.weightKg = 90
        var light = UserProfile.placeholder
        light.weightKg = 50
        let calories = 400.0
        let heavySteps = CalorieEngine.stepsEquivalent(for: calories, profile: heavy)
        let lightSteps = CalorieEngine.stepsEquivalent(for: calories, profile: light)
        XCTAssertGreaterThan(lightSteps, heavySteps,
                             "A 50 kg person must need more steps than a 90 kg person to burn the same calories")
    }
}
