// AppSessionTests.swift
// Pins the contracts the test plan relies on for `AppSession`:
//   - TC-AUTH-08 / TC-UI-21 — DEBUG dev credential matcher.
//   - TC-AUTH-15 — `setAuthenticated` / `clear` round-trip.

import XCTest
@testable import Sweat2Scroll

final class AppSessionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppSession.clear()
    }

    override func tearDown() {
        AppSession.clear()
        super.tearDown()
    }

    // MARK: - dev credential match

    func testDevCredentialsMatch_exact() {
        XCTAssertTrue(AppSession.isDevCredentialMatch(
            username: AppSession.devUsername,
            password: AppSession.devPassword))
    }

    func testDevCredentialsMatch_caseSensitive() {
        // The current implementation is case-sensitive on both fields.
        // If you intend to make it case-insensitive, this test will tell you
        // when behavior changes — flip the assertion intentionally.
        XCTAssertFalse(AppSession.isDevCredentialMatch(
            username: AppSession.devUsername.uppercased(),
            password: AppSession.devPassword))
    }

    func testDevCredentialsMatch_wrongPassword() {
        XCTAssertFalse(AppSession.isDevCredentialMatch(
            username: AppSession.devUsername,
            password: "wrong"))
    }

    func testDevCredentialsMatch_emptyInputs() {
        XCTAssertFalse(AppSession.isDevCredentialMatch(username: "", password: ""))
    }

    // MARK: - session token round-trip

    func testHasSessionToken_falseWhenCleared() {
        AppSession.clear()
        XCTAssertFalse(AppSession.hasSessionToken)
    }

    func testHasSessionToken_trueAfterSetAuthenticated() {
        AppSession.setAuthenticated()
        XCTAssertTrue(AppSession.hasSessionToken)
    }

    func testHasSessionToken_falseAgainAfterClear() {
        AppSession.setAuthenticated()
        AppSession.clear()
        XCTAssertFalse(AppSession.hasSessionToken)
    }
}
