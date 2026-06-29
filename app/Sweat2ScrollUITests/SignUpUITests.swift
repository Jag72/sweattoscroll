// SignUpUITests.swift
// XCUITest scaffold for `SignUpView`. Covers §14.3 of TEST_PLAN.md rows that
// don't require Apple Sign-In or a real CloudKit roundtrip.
//
// Sign Up is the auth root (auth check routes logged-out users here), so each
// test only pays the splash + transition cost before the form is visible.

import XCTest

final class SignUpUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helper

    private func launchToSignUp(file: StaticString = #file,
                                line: UInt = #line) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        XCTAssertTrue(app.textFields["signUp.username"].waitForExistence(timeout: 25),
                      "Sign Up never appeared — did the splash router stall?",
                      file: file, line: line)
        return app
    }

    // MARK: - TC-UI-30 — disabled with empty fields

    func testSignUp_submitDisabledWithEmptyForm() throws {
        let app = try launchToSignUp()
        XCTAssertFalse(app.buttons["signUp.submit"].isEnabled)
    }

    // MARK: - TC-UI-31 — password length

    func testSignUp_submitDisabledWithShortPassword() throws {
        let app = try launchToSignUp()

        app.textFields["signUp.username"].tap()
        app.textFields["signUp.username"].typeText("jag")
        app.secureTextFields["signUp.password"].tap()
        app.secureTextFields["signUp.password"].typeText("12345")  // 5 chars

        XCTAssertFalse(app.buttons["signUp.submit"].isEnabled,
                       "Submit must be disabled when password < 6 chars")
    }

    // MARK: - TC-UI-32 — username length

    func testSignUp_submitDisabledWithShortUsername() throws {
        let app = try launchToSignUp()

        app.textFields["signUp.username"].tap()
        app.textFields["signUp.username"].typeText("jk")  // 2 chars
        app.secureTextFields["signUp.password"].tap()
        app.secureTextFields["signUp.password"].typeText("hunter22")

        XCTAssertFalse(app.buttons["signUp.submit"].isEnabled,
                       "Submit must be disabled when username < 3 chars")
    }

    // MARK: - TC-UI-33 — happy path enables CTA

    func testSignUp_validFormEnablesSubmit() throws {
        let app = try launchToSignUp()

        app.textFields["signUp.username"].tap()
        app.textFields["signUp.username"].typeText("jagkrishna")
        app.secureTextFields["signUp.password"].tap()
        app.secureTextFields["signUp.password"].typeText("hunter22")

        XCTAssertTrue(app.buttons["signUp.submit"].isEnabled)
        // We do NOT actually tap submit — that would hit `EmailCredentialStore`
        // / Keychain / CloudKit and leave persistent state. Submission flow is
        // covered by TC-AUTH-04 / TC-AUTH-05 manually on device.
    }

    // MARK: - TC-UI-36 — Google placeholder alert

    func testSignUp_googleShowsPlaceholderAlert() throws {
        let app = try launchToSignUp()
        app.buttons["signUp.google"].tap()

        let alert = app.alerts["Google Sign-In"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["OK"].tap()
    }

    // MARK: - Forgot Password explanatory alert

    func testSignUp_forgotPasswordShowsAlert() throws {
        let app = try launchToSignUp()
        app.buttons["signUp.forgotPassword"].tap()

        let alert = app.alerts["Reset password"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3),
                      "Forgot Password should show an explanatory alert, not be a silent no-op")
        alert.buttons["OK"].tap()
    }

    // MARK: - TC-UI-37 — push to Sign In

    func testSignUp_goToSignInPushesSignIn() throws {
        let app = try launchToSignUp()
        app.buttons["signUp.goToSignIn"].tap()
        XCTAssertTrue(app.textFields["signIn.username"].waitForExistence(timeout: 5),
                      "Sign In screen did not push after tapping Sign In")
    }

    // MARK: - Intentionally not automated
    //
    //   TC-UI-34 (loading spinner) and TC-UI-35 (Apple sign-up sheet) — same
    //     reasoning as in `SignInUITests.swift`. Verify manually on device.
}
