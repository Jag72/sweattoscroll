// TOTPServiceTests.swift
// Verifies the HOTP/TOTP core against RFC 6238 (SHA-256) test vectors and
// pins the determinism + format invariants the partner-override flow relies
// on (TC-UI-90 / TC-UI-91 / TC-UI-92, TC-ROLE-* OTP semantics).
//
// We bypass the keychain-backed `generateCode()` / `validateCode()` wrappers
// because XCTest in the simulator runs without the production app's
// entitlements; instead we exercise the now-internal `computeHOTP(secret:
// counter:)` and `currentCounter(at:)` directly.

import XCTest
@testable import Sweat2Scroll

final class TOTPServiceTests: XCTestCase {

    // MARK: - RFC 6238 Appendix B vectors (HMAC-SHA-256)
    //
    // The RFC publishes 8-digit TOTP values; HOTP/TOTP truncation produces a
    // 31-bit integer that's reduced by `mod 10^digits`, so the 6-digit
    // expectation is the **last 6 digits** of the published 8-digit value.

    /// `"12345678901234567890123456789012"` (32 ASCII bytes). RFC 6238 test
    /// secret for the SHA-256 mode.
    private var rfcSeedSHA256: Data {
        Data("12345678901234567890123456789012".utf8)
    }

    func testRFC6238_SHA256_T1_sixDigitTrailing() throws {
        // T = 59s. Counter = floor(59 / 30) = 1.
        // RFC 8-digit: 46119246 → 6-digit: 119246
        let code = try TOTPService.computeHOTP(secret: rfcSeedSHA256, counter: 1)
        XCTAssertEqual(code, "119246",
                       "RFC 6238 SHA-256 vector at T=59s mismatched — HMAC or truncation regressed")
    }

    func testRFC6238_SHA256_T1111111109_sixDigitTrailing() throws {
        // T = 1111111109s. Counter = floor(1111111109 / 30) = 37037036.
        // RFC 8-digit: 68084774 → 6-digit: 084774
        let code = try TOTPService.computeHOTP(secret: rfcSeedSHA256, counter: 37037036)
        XCTAssertEqual(code, "084774",
                       "RFC 6238 SHA-256 vector at T=1111111109s mismatched")
    }

    // MARK: - Format invariants

    func testHOTP_alwaysSixDigits() throws {
        // The OTP is `truncatedValue % 10^6`. For small results we must
        // zero-pad to keep the user-visible code six characters wide —
        // otherwise the recipient screen would render "1234" instead of
        // "001234" and `EmergencyOverrideService.redeemGrant` would reject
        // valid codes via its `count == 6` guard.
        let secret = Data(repeating: 0xAA, count: 32)
        for counter in (0 as UInt64)..<200 {
            let code = try TOTPService.computeHOTP(secret: secret, counter: counter)
            XCTAssertEqual(code.count, 6, "Code at counter=\(counter) was '\(code)' — wrong width")
            XCTAssertTrue(code.allSatisfy(\.isNumber),
                          "Code at counter=\(counter) was '\(code)' — non-digit leaked")
        }
    }

    func testHOTP_isDeterministic() throws {
        let secret = Data(repeating: 0x42, count: 32)
        let a = try TOTPService.computeHOTP(secret: secret, counter: 12345)
        let b = try TOTPService.computeHOTP(secret: secret, counter: 12345)
        XCTAssertEqual(a, b)
    }

    func testHOTP_differentCountersGiveDifferentCodes() throws {
        // Statistical: across 100 successive counters with a fixed secret,
        // we should see far more than one distinct code. A regression that
        // makes the counter mixing weak would collapse this set.
        let secret = Data(repeating: 0x33, count: 32)
        var codes: Set<String> = []
        for counter in (0 as UInt64)..<100 {
            codes.insert(try TOTPService.computeHOTP(secret: secret, counter: counter))
        }
        XCTAssertGreaterThan(codes.count, 50,
                             "Counter-mixing collapsed: only \(codes.count) distinct codes in 100 counters")
    }

    func testHOTP_differentSecretsGiveDifferentCodes() throws {
        let counter: UInt64 = 42
        let a = try TOTPService.computeHOTP(secret: Data(repeating: 0x01, count: 32), counter: counter)
        let b = try TOTPService.computeHOTP(secret: Data(repeating: 0x02, count: 32), counter: counter)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - currentCounter(at:)

    func testCurrentCounter_t0() {
        let counter = TOTPService.currentCounter(at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(counter, 0)
    }

    func testCurrentCounter_t29ReturnsZero() {
        // Within the first 30s window: floor(29 / 30) = 0.
        XCTAssertEqual(TOTPService.currentCounter(at: Date(timeIntervalSince1970: 29)), 0)
    }

    func testCurrentCounter_t30ReturnsOne() {
        XCTAssertEqual(TOTPService.currentCounter(at: Date(timeIntervalSince1970: 30)), 1)
    }

    func testCurrentCounter_advanceMatchesTimeStepSeconds() {
        // Sanity-check: `timeStepSeconds` is the only thing that can shift
        // the counter cadence. Pin its value in case it's accidentally
        // changed (which would invalidate every existing TOTP secret).
        XCTAssertEqual(TOTPService.timeStepSeconds, 30)
    }

    // MARK: - Drift tolerance contract

    func testDriftToleranceConstant() {
        // The validator accepts current counter ± `driftTolerance`. Cap the
        // drift at 1 step (30s) so a partner with a clock drifting by more
        // than that is forced to fix it instead of silently bypassing the
        // expiry boundary.
        XCTAssertEqual(TOTPService.driftTolerance, 1)
    }
}
