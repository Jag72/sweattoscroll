// Services/PairingService.swift
// 6-digit pairing: monitor generates code → user enters → CloudKit links both UserAccount rows.

import Foundation
import CloudKit

@MainActor
final class PairingService: ObservableObject {
    static let shared = PairingService()

    private let cloud = CloudKitService.shared
    private let codeTTL: TimeInterval = 600

    /// Generates a random 6-digit code, persists to CloudKit with TTL.
    func generateCode(forMonitorID monitorAppleUserID: String) async throws -> String {
        let code = String(format: "%06d", Int.random(in: 100_000...999_999))
        let expires = Date().addingTimeInterval(codeTTL)
        try await cloud.savePairCodeRecord(code: code, monitorAppleUserID: monitorAppleUserID, expiresAt: expires)
        return code
    }

    /// Validates code, links monitor ↔ user on success.
    func validateAndPair(code: String, userAppleUserID: String) async throws -> PairingResult {
        let normalized = code.filter(\.isNumber)
        guard normalized.count == 6 else { return .invalid }

        guard let record = await cloud.fetchPairCodeRecord(code: normalized) else {
            return .invalid
        }

        if (record["consumed"] as? Int64 ?? 1) != 0 {
            return .invalid
        }

        guard let expires = record["expiresAt"] as? Date, expires > Date() else {
            await cloud.deletePairCodeRecord(recordID: record.recordID)
            return .expired
        }

        guard let monitorID = record["monitorAppleUserID"] as? String, !monitorID.isEmpty else {
            return .invalid
        }

        if monitorID == userAppleUserID {
            return .invalid
        }

        guard var userAcc = await cloud.fetchUserAccount(appleUserID: userAppleUserID),
              var monitorAcc = await cloud.fetchUserAccount(appleUserID: monitorID) else {
            return .invalid
        }

        userAcc.linkedPeerAppleUserID = monitorID
        userAcc.isPaired = true
        monitorAcc.linkedPeerAppleUserID = userAppleUserID
        monitorAcc.isPaired = true

        try await cloud.saveUserAccount(userAcc)
        try await cloud.saveUserAccount(monitorAcc)

        await cloud.deletePairCodeRecord(recordID: record.recordID)

        return .success(linkedMonitorID: monitorID)
    }

    /// Polls until the monitor sees pairing (user completed `validateAndPair`).
    func pollForPairingConfirmation(monitorAppleUserID: String) async -> Bool {
        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            if let acc = await cloud.fetchUserAccount(appleUserID: monitorAppleUserID),
               acc.isPaired,
               acc.linkedPeerAppleUserID != nil {
                return true
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        return false
    }
}
