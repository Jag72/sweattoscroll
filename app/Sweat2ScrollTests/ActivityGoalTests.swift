import XCTest
@testable import Sweat2Scroll

final class ActivityGoalTests: XCTestCase {

    func testProgressFractionCapsAtOne() {
        var g = ActivityGoal.placeholder
        g.agreedTarget = 300
        g.currentProgress = 900
        XCTAssertEqual(g.progressFraction, 1.0)
        XCTAssertTrue(g.isUnlocked)
    }

    func testProgressFractionZeroWhenNoTarget() {
        var g = ActivityGoal.placeholder
        g.agreedTarget = 0
        g.currentProgress = 50
        XCTAssertEqual(g.progressFraction, 0)
        XCTAssertFalse(g.isUnlocked)
    }

    func testRemainingNeverNegative() {
        var g = ActivityGoal.placeholder
        g.agreedTarget = 100
        g.currentProgress = 200
        XCTAssertEqual(g.remaining, 0)
    }
}
