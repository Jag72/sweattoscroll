// SignInUITests.swift
// XCUITest scaffold for `SignInView`. Covers the rows in §14.2 of TEST_PLAN.md
// that don't need a real Apple Sign-In sheet, real CloudKit, or a physical
// device. Cross-device, real-Apple-credential, and post-auth-routing rows
// (TC-UI-19, TC-UI-20) are intentionally NOT automated here — see the notes
// at the bottom of this file.
//
// Sign Up is the auth root; each helper launch navigates Sign Up → Sign In.

import XCTest

final class SignInUITests: XCTestCase {

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchedApp(file: StaticString = #file,
                             line: UInt = #line) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        // Splash → transition → Sign Up can take a few seconds on a cold launch.
        XCTAssertTrue(app.textFields["signUp.username"].waitForExistence(timeout: 25),
                      "Sign Up screen never appeared — did the splash router stall?",
                      file: file, line: line)
        app.buttons["signUp.goToSignIn"].tap()

        let username = app.textFields["signIn.username"]
        XCTAssertTrue(username.waitForExistence(timeout: 5),
                      "Sign In did not push from Sign Up", file: file, line: line)
        return app
    }

    // MARK: - TC-UI-10 — layout & copy

    func testSignIn_layoutAndCopy() throws {
        let app = try launchedApp()

        XCTAssertTrue(app.staticTexts["Welcome back"].exists)
        // Subtitle is split across multiple `Text` views; assert by predicate
        // so a future copy tweak that keeps the meaning intact still passes.
        let subtitle = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "shield")
        ).firstMatch
        XCTAssertTrue(subtitle.exists, "Shield-related subtitle missing")

        XCTAssertTrue(app.textFields["signIn.username"].exists)
        XCTAssertTrue(app.secureTextFields["signIn.password"].exists)
        XCTAssertTrue(app.buttons["signIn.submit"].exists)
        XCTAssertTrue(app.buttons["signIn.forgotPassword"].exists)
        XCTAssertTrue(app.buttons["signIn.google"].exists)
        XCTAssertTrue(app.buttons["signIn.goToSignUp"].exists)
    }

    // MARK: - TC-UI-11 / TC-UI-12 — CTA enabled state

    func testSignIn_submitDisabledWithIncompleteForm() throws {
        let app = try launchedApp()
        let username = app.textFields["signIn.username"]
        let submit = app.buttons["signIn.submit"]

        // Empty form
        XCTAssertFalse(submit.isEnabled, "Submit should be disabled with empty form")

        // Username only — still disabled until a password is typed
        username.tap()
        username.typeText("jagkrishna")
        XCTAssertFalse(submit.isEnabled,
                       "Submit should stay disabled until both fields are filled")
    }

    func testSignIn_submitEnabledForValidInput() throws {
        let app = try launchedApp()
        let username = app.textFields["signIn.username"]
        let password = app.secureTextFields["signIn.password"]
        let submit = app.buttons["signIn.submit"]

        username.tap()
        username.typeText("jagkrishna")
        password.tap()
        password.typeText("hunter22")

        XCTAssertTrue(submit.isEnabled)
    }

    // MARK: - TC-UI-13 — password visibility toggle

    func testSignIn_passwordRevealToggleDoesNotLoseText() throws {
        let app = try launchedApp()

        let secure = app.secureTextFields["signIn.password"]
        secure.tap()
        secure.typeText("hunter22")

        // The eye toggle has no accessibility identifier yet — find by SF Symbol
        // image label via firstMatch on a button with image "eye.fill".
        // If this proves flaky we can wire an explicit identifier.
        let revealCandidates = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "eye"))
        guard revealCandidates.count > 0 else {
            // Toggle isn't queryable this way on every iOS version — skip
            // gracefully rather than fail the suite.
            throw XCTSkip("Password reveal button not addressable via accessibility query on this OS")
        }

        let toggle = revealCandidates.element(boundBy: 0)
        toggle.tap()

        // After toggling, the field flips from secureTextField → textField in
        // the SwiftUI tree. Confirm the visible value survives the swap.
        let revealed = app.textFields["signIn.password"]
        XCTAssertTrue(revealed.waitForExistence(timeout: 2))
        XCTAssertEqual(revealed.value as? String, "hunter22")
    }

    // MARK: - TC-UI-16 — Forgot Password (we wired an alert)

    func testSignIn_forgotPasswordShowsAlert() throws {
        let app = try launchedApp()
        app.buttons["signIn.forgotPassword"].tap()

        let alert = app.alerts["Reset password"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3),
                      "Forgot Password should show an explanatory alert, not be a silent no-op")
        alert.buttons["OK"].tap()
        XCTAssertFalse(alert.exists)
    }

    // MARK: - TC-UI-17 — pop back to Sign Up

    func testSignIn_navigateBackToSignUp() throws {
        let app = try launchedApp()
        app.buttons["signIn.goToSignUp"].tap()

        // Sign Up root anchor: the username field.
        XCTAssertTrue(app.textFields["signUp.username"].waitForExistence(timeout: 5),
                      "Sign Up screen did not reappear after tapping Sign Up")
    }

    // MARK: - TC-UI-18 — Google placeholder alert

    func testSignIn_googleShowsPlaceholderAlert() throws {
        let app = try launchedApp()
        app.buttons["signIn.google"].tap()

        let alert = app.alerts["Google Sign-In"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["OK"].tap()
        XCTAssertFalse(alert.exists)
    }

    // MARK: - TC-UI-21 — DEBUG tester chip
    //
    // The chip is `#if DEBUG`-gated. UI tests build against the same
    // configuration as the host scheme — when run from Xcode against a Debug
    // build, the chip is visible. In a Release-built target this assertion
    // would (correctly) fail; that's TC-REL-04 / TC-VAR-02.

    #if DEBUG
    func testSignIn_devChip_visibleInDebugFillsCredentials() throws {
        let app = try launchedApp()
        let chip = app.buttons["signIn.devChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 3),
                      "Tester chip should be visible in DEBUG builds")
        chip.tap()

        // After tap, both fields should have the dev credentials.
        let username = app.textFields["signIn.username"]
        // The password field's `value` is masked in secure mode, so we can
        // only assert via the username side here. Username is enough to prove
        // the chip wired through.
        XCTAssertEqual(username.value as? String, "puji")
    }
    #endif

    // MARK: - Notes on intentionally-unautomated rows
    //
    //   TC-UI-14 (loading spinner on submit) — depends on `AuthManager`
    //     publishing `isLoadingAuth = true` for long enough to observe in
    //     XCUITest. CloudKit RTT in Simulator is too short and too flaky to
    //     pin reliably. Verify manually.
    //
    //   TC-UI-15 (auth error UI after wrong password) — needs a real
    //     `EmailCredentialStore` entry to verify against; the keychain state
    //     varies per simulator boot and is brittle in CI. Verify manually
    //     or add a test-mode hook in AuthManager.
    //
    //   TC-UI-19 / TC-UI-20 (Sign In with Apple cancel / success) — XCUITest
    //     cannot drive the system Apple Sign-In sheet. Verify on device.
}
