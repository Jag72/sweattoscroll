import XCTest
@testable import Sweat2Scroll

final class CalorieEngineTests: XCTestCase {

    func testComputeGoalAdultMaleClampedToHardCap() {
        var p = UserProfile.placeholder
        p.weightKg = 120
        p.heightCm = 190
        p.ageYears = 30
        p.biologicalSex = .male

        let goal = CalorieEngine.computeGoal(for: p)
        XCTAssertEqual(goal.hardCap, CalorieEngine.adultHardCap)
        XCTAssertLessThanOrEqual(goal.agreedTarget, CalorieEngine.adultHardCap)
        XCTAssertGreaterThan(goal.agreedTarget, 0)
    }

    func testPediatricUsesLowerHardCap() {
        var p = UserProfile.placeholder
        p.ageYears = 10
        p.weightKg = 35
        p.heightCm = 140
        p.biologicalSex = .female

        let goal = CalorieEngine.computeGoal(for: p)
        XCTAssertEqual(goal.hardCap, CalorieEngine.pediatricHardCap)
        XCTAssertLessThanOrEqual(goal.agreedTarget, CalorieEngine.pediatricHardCap)
    }

    func testStepsEquivalentPositive() {
        var p = UserProfile.placeholder
        p.weightKg = 70
        let steps = CalorieEngine.stepsEquivalent(for: 400, profile: p)
        XCTAssertGreaterThan(steps, 0)
    }
}
