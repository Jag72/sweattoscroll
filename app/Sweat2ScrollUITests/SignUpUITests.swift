// SignUpUITests.swift
// XCUITest scaffold for `SignUpView`. Covers §14.3 of TEST_PLAN.md rows that
// don't require Apple Sign-In or a real CloudKit roundtrip.
//
// All tests start by reaching Sign Up via the Sign In sheet — no deep-linking
// shortcut yet exists, so each test pays the splash + nav cost once.

import XCTest

final class SignUpUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helper

    private func launchAndOpenSignUp(file: StaticString = #file,
                                     line: UInt = #line) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let signInEmail = app.textFields["signIn.email"]
        XCTAssertTrue(signInEmail.waitForExistence(timeout: 25),
                      "Sign In never appeared", file: file, line: line)
        app.buttons["signIn.goToSignUp"].tap()

        XCTAssertTrue(app.textFields["signUp.firstName"].waitForExistence(timeout: 5),
                      "Sign Up sheet did not open", file: file, line: line)
        return app
    }

    // MARK: - TC-UI-30 — disabled with empty fields

    func testSignUp_submitDisabledWithEmptyForm() throws {
        let app = try launchAndOpenSignUp()
        XCTAssertFalse(app.buttons["signUp.submit"].isEnabled)
    }

    // MARK: - TC-UI-31 — password length

    func testSignUp_submitDisabledWithShortPassword() throws {
        let app = try launchAndOpenSignUp()

        app.textFields["signUp.firstName"].tap()
        app.textFields["signUp.firstName"].typeText("Jag")
        app.textFields["signUp.lastName"].tap()
        app.textFields["signUp.lastName"].typeText("K")
        app.textFields["signUp.email"].tap()
        app.textFields["signUp.email"].typeText("jag@example.com")
        app.secureTextFields["signUp.password"].tap()
        app.secureTextFields["signUp.password"].typeText("12345")  // 5 chars
        app.secureTextFields["signUp.confirmPassword"].tap()
        app.secureTextFields["signUp.confirmPassword"].typeText("12345")

        XCTAssertFalse(app.buttons["signUp.submit"].isEnabled,
                       "Submit must be disabled when password < 6 chars")
    }

    // MARK: - TC-UI-32 — password mismatch label

    func testSignUp_passwordMismatchLabelAppears() throws {
        let app = try launchAndOpenSignUp()

        app.secureTextFields["signUp.password"].tap()
        app.secureTextFields["signUp.password"].typeText("hunter22")
        app.secureTextFields["signUp.confirmPassword"].tap()
        app.secureTextFields["signUp.confirmPassword"].typeText("differs!")

        let mismatch = app.staticTexts["signUp.passwordMismatch"]
        XCTAssertTrue(mismatch.waitForExistence(timeout: 2),
                      "Mismatch label must appear once confirm is non-empty and differs")
        XCTAssertTrue(app.buttons["signUp.submit"].isEnabled == false)
    }

    // MARK: - TC-UI-33 — happy path enables CTA

    func testSignUp_validFormEnablesSubmit() throws {
        let app = try launchAndOpenSignUp()

        app.textFields["signUp.firstName"].tap()
        app.textFields["signUp.firstName"].typeText("Jag")
        app.textFields["signUp.lastName"].tap()
        app.textFields["signUp.lastName"].typeText("Krishna")
        app.textFields["signUp.email"].tap()
        app.textFields["signUp.email"].typeText("jag@example.com")
        app.secureTextFields["signUp.password"].tap()
        app.secureTextFields["signUp.password"].typeText("hunter22")
        app.secureTextFields["signUp.confirmPassword"].tap()
        app.secureTextFields["signUp.confirmPassword"].typeText("hunter22")

        XCTAssertTrue(app.buttons["signUp.submit"].isEnabled)
        // We do NOT actually tap submit — that would hit `EmailCredentialStore`
        // / Keychain / CloudKit and leave persistent state. Submission flow is
        // covered by TC-AUTH-04 / TC-AUTH-05 manually on device.
    }

    // MARK: - TC-UI-36 — Google placeholder alert

    func testSignUp_googleShowsPlaceholderAlert() throws {
        let app = try launchAndOpenSignUp()
        app.buttons["signUp.google"].tap()

        let alert = app.alerts["Google Sign-In"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["OK"].tap()
    }

    // MARK: - TC-UI-37 — back to Sign In

    func testSignUp_backToSignInDismissesSheet() throws {
        let app = try launchAndOpenSignUp()
        app.buttons["signUp.backToSignIn"].tap()
        XCTAssertTrue(app.textFields["signIn.email"].waitForExistence(timeout: 5))
    }

    // MARK: - Intentionally not automated
    //
    //   TC-UI-34 (loading spinner) and TC-UI-35 (Apple sign-up sheet) — same
    //     reasoning as in `SignInUITests.swift`. Verify manually on device.
}
