// PairingServiceTests.swift
// Pure-logic coverage for `PairingService.normalizeCode(_:)` — the input
// guard that decides whether a typed-in pairing code is even shaped right
// before we waste a CloudKit round-trip looking it up. Cross-device pairing
// (the rest of `validateAndPair`) needs two CloudKit accounts and is
// covered manually in TEST_PLAN §9 / §14.8.

import XCTest
@testable import Sweat2Scroll

// The tested type is @MainActor-isolated; hop the whole suite onto the
// main actor so calls to its statics compile under strict concurrency.
@MainActor
final class PairingServiceTests: XCTestCase {

    // MARK: - Valid input

    func testNormalize_sixDigits() {
        XCTAssertEqual(PairingService.normalizeCode("123456"), "123456")
    }

    func testNormalize_acceptsLeadingZeros() {
        // Pairing codes are formatted via `%06d` from a random Int.
        // The format pads small numbers, so "000123" must round-trip
        // verbatim — otherwise the receiver couldn't redeem a code
        // generated for `Int.random(in: 100_000...999_999)` is fine but
        // forward-compatible with any future zero-padded scheme.
        XCTAssertEqual(PairingService.normalizeCode("000123"), "000123")
    }

    func testNormalize_stripsSpaces() {
        XCTAssertEqual(PairingService.normalizeCode("123 456"), "123456")
        XCTAssertEqual(PairingService.normalizeCode(" 123456 "), "123456")
    }

    func testNormalize_stripsDashesAndPunctuation() {
        XCTAssertEqual(PairingService.normalizeCode("123-456"), "123456")
        XCTAssertEqual(PairingService.normalizeCode("12.34.56"), "123456")
    }

    func testNormalize_stripsLettersIfRemainingDigitsExactlySix() {
        // The implementation calls `code.filter(\.isNumber)` then checks
        // `count == 6`. So embedded letters that leave six digits behind
        // pass — but anything that doesn't yield exactly 6 digits fails.
        XCTAssertEqual(PairingService.normalizeCode("a1b2c3d4e5f6"), "123456")
    }

    // MARK: - Invalid input

    func testNormalize_empty() {
        XCTAssertNil(PairingService.normalizeCode(""))
    }

    func testNormalize_tooShort() {
        XCTAssertNil(PairingService.normalizeCode("12345"))
        XCTAssertNil(PairingService.normalizeCode("1"))
    }

    func testNormalize_tooLong() {
        XCTAssertNil(PairingService.normalizeCode("1234567"))
        XCTAssertNil(PairingService.normalizeCode("123456789"))
    }

    func testNormalize_lettersOnly() {
        XCTAssertNil(PairingService.normalizeCode("abcdef"))
    }

    func testNormalize_unicodeDigitsCount() {
        // `Character.isNumber` covers every Unicode-numeric character (e.g.
        // Arabic-Indic, fullwidth). Stripping non-digits then checking
        // `count == 6` makes the function permissive about the script —
        // pin that behavior so a future tightening to ASCII-only is a
        // conscious choice, not a silent regression.
        let mixed = "1٢3456"  // ASCII '1', Arabic-Indic '٢', then 3-6
        XCTAssertEqual(PairingService.normalizeCode(mixed)?.count, 6)
    }

    // MARK: - PairingResult enum is the contract surface

    func testPairingResult_invalidEqualsInvalid() {
        // Sanity check on Equatable conformance — pairing UI compares
        // results to drive UX branches.
        XCTAssertEqual(PairingResult.invalid, PairingResult.invalid)
        XCTAssertEqual(PairingResult.expired, PairingResult.expired)
        XCTAssertNotEqual(PairingResult.invalid, PairingResult.expired)
    }

    func testPairingResult_successCarriesMonitorID() {
        let s = PairingResult.success(linkedMonitorID: "monitor-abc")
        if case let .success(id) = s {
            XCTAssertEqual(id, "monitor-abc")
        } else {
            XCTFail("Expected .success case")
        }
    }
}
