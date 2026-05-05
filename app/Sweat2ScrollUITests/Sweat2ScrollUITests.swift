import XCTest

/// UI tests run on a real device or simulator. FamilyControls / shield flows cannot be fully
/// automated on simulator; these tests focus on launch resilience and auth chrome.
final class Sweat2ScrollUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch_reachesSignInChrome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        // Splash → transition → Sign In can take a few seconds on cold launch.
        let email = app.textFields["signIn.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 25))

        let signIn = app.buttons["signIn.submit"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertFalse(signIn.isEnabled)
    }
}
