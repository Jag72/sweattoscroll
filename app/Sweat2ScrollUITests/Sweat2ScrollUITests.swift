import XCTest

/// UI tests run on a real device or simulator. FamilyControls / shield flows cannot be fully
/// automated on simulator; these tests focus on launch resilience and auth chrome.
final class Sweat2ScrollUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch_reachesSignUpChrome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        // Splash → transition → Sign Up can take a few seconds on cold launch.
        let username = app.textFields["signUp.username"]
        XCTAssertTrue(username.waitForExistence(timeout: 25))

        let signUp = app.buttons["signUp.submit"]
        XCTAssertTrue(signUp.waitForExistence(timeout: 5))
        XCTAssertFalse(signUp.isEnabled)
    }
}
