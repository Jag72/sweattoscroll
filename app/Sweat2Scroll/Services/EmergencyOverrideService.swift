// Services/EmergencyOverrideService.swift
// Partner-to-partner "break-glass" override flow used after a successful pairing.
//
// One side (the *granter*) generates a random 6-digit code, picks how many
// minutes of unblock time they want to grant, and writes a `BypassGrant` record
// to CloudKit. The other side (the *recipient*) types the code in; we look up
// the matching CloudKit record, verify expiry + scope, mark it consumed, and
// trigger `ScreenTimeService.temporaryBypass(minutes:)` for the granted duration.
//
// Unlike `TOTPService`, this flow does not require ECDH or a pre-shared secret —
// it works with the existing 6-digit pairing flow that already links accounts
// over CloudKit.

import Foundation

// MARK: - Grant payload
/// Persisted to CloudKit as a `BypassGrant` record. Both partners can read it
/// because each device is signed into the same shared private DB context (the
/// CKShare zone established during pairing).
struct EmergencyOverrideGrant: Identifiable, Codable, Equatable {
    let id: UUID
    let code: String
    let partnershipID: String
    let granterUserID: String
    let granterDisplayName: String
    let recipientUserID: String
    let durationMinutes: Int
    let reason: String?
    let createdAt: Date
    let expiresAt: Date

    /// Stable identifier used to scope grants between the same two devices —
    /// independent of which side initiated pairing.
    static func partnershipID(a: String, b: String) -> String {
        [a, b].sorted().joined(separator: "|")
    }
}

// MARK: - Errors

enum EmergencyOverrideError: LocalizedError {
    case invalidCode
    case expired
    case unpaired
    case roleDoesNotPermit
    case cloudUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "Invalid code. Ask your partner for a fresh one."
        case .expired:
            return "Code expired. Ask your partner to send a new one."
        case .unpaired:
            return "You aren't paired with a partner yet."
        case .roleDoesNotPermit:
            return "Your partnership role doesn't allow this action."
        case .cloudUnavailable:
            return "iCloud is unreachable. Check your connection and try again."
        }
    }
}

// MARK: - Service

@MainActor
final class EmergencyOverrideService: ObservableObject {
    static let shared = EmergencyOverrideService()

    /// Codes expire shortly after issuing — the recipient is meant to act on
    /// them right away, not save them for later.
    private let codeTTL: TimeInterval = 10 * 60

    /// Inclusive bounds applied to the granter's requested duration. 5 min
    /// is the lowest useful unblock; 4 hours is the highest a partner should
    /// be able to grant before the receiving side is forced to ask again.
    /// Exposed as constants so XCTest can pin the contract.
    static let minGrantMinutes: Int = 5
    static let maxGrantMinutes: Int = 240

    /// Clamps a partner-supplied minute value to the safe issue-grant range.
    /// Pure / static so tests can verify the contract without spinning up
    /// CloudKit. If you change the bounds, update TC-UI-90/91 in TEST_PLAN.
    static func clampedDurationMinutes(_ raw: Int) -> Int {
        max(minGrantMinutes, min(raw, maxGrantMinutes))
    }

    private let cloud = CloudKitService.shared

    // MARK: Issue (granter side)

    /// Issues a fresh 6-digit OTP that the recipient can redeem to unlock their
    /// blocked apps for `durationMinutes`. Persists the grant to CloudKit so the
    /// recipient's device can validate it without trusting local input.
    @discardableResult
    func issueGrant(granterUserID: String,
                    granterDisplayName: String,
                    recipientUserID: String,
                    durationMinutes: Int,
                    reason: String?) async throws -> EmergencyOverrideGrant {
        guard !granterUserID.isEmpty, !recipientUserID.isEmpty else {
            throw EmergencyOverrideError.unpaired
        }
        let clampedDuration = Self.clampedDurationMinutes(durationMinutes)
        let code = String(format: "%06d", Int.random(in: 100_000...999_999))
        let now = Date()
        let grant = EmergencyOverrideGrant(
            id: UUID(),
            code: code,
            partnershipID: EmergencyOverrideGrant.partnershipID(a: granterUserID, b: recipientUserID),
            granterUserID: granterUserID,
            granterDisplayName: granterDisplayName,
            recipientUserID: recipientUserID,
            durationMinutes: clampedDuration,
            reason: reason?.isEmpty == false ? reason : nil,
            createdAt: now,
            expiresAt: now.addingTimeInterval(codeTTL)
        )
        try await cloud.saveBypassGrant(grant)
        return grant
    }

    // MARK: Redeem (recipient side)

    /// Validates a 6-digit OTP issued by the recipient's partner. On success,
    /// returns the matching grant (caller should call
    /// `ScreenTimeService.temporaryBypass(minutes:)` with `grant.durationMinutes`).
    func redeemGrant(code: String,
                     recipientUserID: String,
                     partnerUserID: String) async throws -> EmergencyOverrideGrant {
        guard !recipientUserID.isEmpty, !partnerUserID.isEmpty else {
            throw EmergencyOverrideError.unpaired
        }
        let normalized = code.filter(\.isNumber)
        guard normalized.count == 6 else { throw EmergencyOverrideError.invalidCode }

        let pairID = EmergencyOverrideGrant.partnershipID(a: recipientUserID, b: partnerUserID)
        guard let grant = await cloud.fetchBypassGrant(code: normalized, partnershipID: pairID) else {
            throw EmergencyOverrideError.invalidCode
        }
        guard grant.recipientUserID == recipientUserID else {
            throw EmergencyOverrideError.invalidCode
        }
        guard grant.expiresAt > Date() else {
            await cloud.consumeBypassGrant(recordName: grant.id.uuidString)
            throw EmergencyOverrideError.expired
        }
        await cloud.consumeBypassGrant(recordName: grant.id.uuidString)
        return grant
    }
}
