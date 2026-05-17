// EmergencyOverrideTests.swift
// Pure-logic coverage for the partner-to-partner break-glass override flow.
// CloudKit-dependent paths (`issueGrant`, `redeemGrant`, expiry handling)
// require a real CKDatabase or a mock; those rows are tracked in TEST_PLAN
// §14.9 / §14.12 as manual-on-device. This file pins the parts that don't
// touch the network.

import XCTest
@testable import Sweat2Scroll

final class EmergencyOverrideTests: XCTestCase {

    // MARK: - partnershipID

    func testPartnershipID_isSymmetric() {
        // The partnership ID must be the same regardless of which side
        // initiated pairing — otherwise the recipient's redeem query would
        // fail to find the granter's saved bypass record.
        let ab = EmergencyOverrideGrant.partnershipID(a: "alice", b: "bob")
        let ba = EmergencyOverrideGrant.partnershipID(a: "bob", b: "alice")
        XCTAssertEqual(ab, ba)
    }

    func testPartnershipID_distinctForDifferentPairs() {
        let pair1 = EmergencyOverrideGrant.partnershipID(a: "alice", b: "bob")
        let pair2 = EmergencyOverrideGrant.partnershipID(a: "alice", b: "carol")
        XCTAssertNotEqual(pair1, pair2)
    }

    func testPartnershipID_usesSeparatorBetweenIDs() {
        // The format is `sorted([a,b]).joined("|")` — verify the literal
        // shape so a future refactor doesn't break already-saved
        // BypassGrant records on the server.
        XCTAssertEqual(
            EmergencyOverrideGrant.partnershipID(a: "alice", b: "bob"),
            "alice|bob"
        )
        XCTAssertEqual(
            EmergencyOverrideGrant.partnershipID(a: "z", b: "a"),
            "a|z"
        )
    }

    func testPartnershipID_emptyStringsHandled() {
        // Defensive: passing empty IDs shouldn't crash. We don't make a
        // claim about the result — `EmergencyOverrideService.redeemGrant`
        // already rejects empty IDs upstream — but the partnership-ID
        // helper itself must remain pure.
        XCTAssertNoThrow(_ = EmergencyOverrideGrant.partnershipID(a: "", b: "bob"))
        XCTAssertNoThrow(_ = EmergencyOverrideGrant.partnershipID(a: "", b: ""))
    }

    // MARK: - clampedDurationMinutes

    func testClampedDuration_pinnedBoundaries() {
        // These constants are referenced by name in TC-UI-90/91. Pin them
        // so a silent change is caught at test time.
        XCTAssertEqual(EmergencyOverrideService.minGrantMinutes, 5)
        XCTAssertEqual(EmergencyOverrideService.maxGrantMinutes, 240)
    }

    func testClampedDuration_belowMinimumIsRaised() {
        XCTAssertEqual(EmergencyOverrideService.clampedDurationMinutes(0), 5)
        XCTAssertEqual(EmergencyOverrideService.clampedDurationMinutes(1), 5)
        XCTAssertEqual(EmergencyOverrideService.clampedDurationMinutes(-30), 5)
    }

    func testClampedDuration_aboveMaximumIsLowered() {
        XCTAssertEqual(EmergencyOverrideService.clampedDurationMinutes(241), 240)
        XCTAssertEqual(EmergencyOverrideService.clampedDurationMinutes(10_000), 240)
    }

    func testClampedDuration_withinRangeUnchanged() {
        XCTAssertEqual(EmergencyOverrideService.clampedDurationMinutes(5), 5)
        XCTAssertEqual(EmergencyOverrideService.clampedDurationMinutes(15), 15)
        XCTAssertEqual(EmergencyOverrideService.clampedDurationMinutes(60), 60)
        XCTAssertEqual(EmergencyOverrideService.clampedDurationMinutes(240), 240)
    }

    // MARK: - Codable round-trip
    //
    // The grant is saved to CloudKit as a CKRecord (not directly via
    // Codable), but it's also passed across the in-process boundary
    // (notifications, in-memory queues) and may be cached locally. Pin
    // its Codable round-trip so neither path silently drops a field.

    func testGrant_codableRoundTrip() throws {
        let now = Date()
        let original = EmergencyOverrideGrant(
            id: UUID(),
            code: "012345",
            partnershipID: "alice|bob",
            granterUserID: "bob",
            granterDisplayName: "Bob",
            recipientUserID: "alice",
            durationMinutes: 30,
            reason: "emergency call",
            createdAt: now,
            expiresAt: now.addingTimeInterval(600)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(EmergencyOverrideGrant.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.code, original.code)
        XCTAssertEqual(decoded.partnershipID, original.partnershipID)
        XCTAssertEqual(decoded.granterUserID, original.granterUserID)
        XCTAssertEqual(decoded.granterDisplayName, original.granterDisplayName)
        XCTAssertEqual(decoded.recipientUserID, original.recipientUserID)
        XCTAssertEqual(decoded.durationMinutes, original.durationMinutes)
        XCTAssertEqual(decoded.reason, original.reason)
        // Dates: ISO-8601 round-trip can drop sub-second precision; use a
        // 1-second tolerance window.
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970,
                       original.createdAt.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(decoded.expiresAt.timeIntervalSince1970,
                       original.expiresAt.timeIntervalSince1970, accuracy: 1.0)
    }
}
