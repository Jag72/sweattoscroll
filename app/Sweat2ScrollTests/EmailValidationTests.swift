// EmailValidationTests.swift
// Covers `SignUpView.isValidEmail` — decides whether an email-shaped
// username also lands in the CloudKit `email` slot (see `AuthManager.signUp`
// / `signIn`), so format edge cases still matter after the username switch.

import XCTest
@testable import Sweat2Scroll

// The tested type is @MainActor-isolated; hop the whole suite onto the
// main actor so calls to its statics compile under strict concurrency.
@MainActor
final class EmailValidationTests: XCTestCase {

    // MARK: - Valid

    func testValidEmail_basic() {
        XCTAssertTrue(SignUpView.isValidEmail("a@b.co"))
    }

    func testValidEmail_withDotsAndPlus() {
        XCTAssertTrue(SignUpView.isValidEmail("first.last+tag@example.co.uk"))
    }

    func testValidEmail_uppercaseAccepted() {
        XCTAssertTrue(SignUpView.isValidEmail("USER@EXAMPLE.COM"))
    }

    func testValidEmail_trimsSurroundingWhitespace() {
        XCTAssertTrue(SignUpView.isValidEmail("  user@example.com  "))
        XCTAssertTrue(SignUpView.isValidEmail("\tuser@example.com\n"))
    }

    // MARK: - Invalid

    func testInvalidEmail_empty() {
        XCTAssertFalse(SignUpView.isValidEmail(""))
        XCTAssertFalse(SignUpView.isValidEmail("   "))
    }

    func testInvalidEmail_missingAtSign() {
        XCTAssertFalse(SignUpView.isValidEmail("userexample.com"))
    }

    func testInvalidEmail_missingDot() {
        XCTAssertFalse(SignUpView.isValidEmail("user@example"))
    }

    func testInvalidEmail_singleCharTLD() {
        // pattern requires `[A-Za-z]{2,}` for TLD
        XCTAssertFalse(SignUpView.isValidEmail("user@example.c"))
    }

    func testInvalidEmail_tooShort() {
        // length floor is 5 — "a@b.c" is 5 but TLD must be >= 2
        XCTAssertFalse(SignUpView.isValidEmail("a@b.c"))
        XCTAssertFalse(SignUpView.isValidEmail("a@b"))
    }

    func testInvalidEmail_devCredentialPlaintext_TC_UI_123() {
        // Release safety: the DEBUG-only "puji" / "1234" shortcut lives in
        // `AppSession`, but the code path that consumes it in `signInEmail()`
        // is `#if DEBUG`-gated. As an extra defense, `isValidEmail("puji")`
        // must return false so the Sign In CTA stays disabled in Release
        // even if a curious user types the dev login.
        XCTAssertFalse(SignUpView.isValidEmail("puji"))
        XCTAssertFalse(SignUpView.isValidEmail(AppSession.devUsername))
    }
}
