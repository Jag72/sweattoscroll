// Models/GovernanceContract.swift
// Represents the cryptographic governance contract between two Mutual Controllers.
// Stored in CloudKit CKShare and encrypted via encryptedValues.

import Foundation
import CloudKit

struct GovernanceContract: Codable, Identifiable {
    var id: UUID = UUID()

    // Device A (self)
    var controlledUserID: String       // iCloud record name
    var controlledDisplayName: String

    // Device B (partner)
    var controllerUserID: String
    var controllerDisplayName: String

    // Contract terms
    var goalCurrency: GoalCurrency
    var agreedDailyTarget: Double
    var hardCap: Double
    var maxRestrictedApps: Int = 10

    // Pairing metadata
    var pairedAt: Date
    var contractVersion: String = "1.0"

    // CloudKit zone name for CKShare
    var cloudKitZoneName: String {
        "GovernanceZone-\(id.uuidString)"
    }

    // Shared secret fingerprint (NOT the secret itself — stored in Secure Enclave)
    // Used only to verify both parties share the same key
    var sharedSecretFingerprint: String

    static let placeholder = GovernanceContract(
        controlledUserID: "user-a",
        controlledDisplayName: "You",
        controllerUserID: "user-b",
        controllerDisplayName: "Partner",
        goalCurrency: .activeCalories,
        agreedDailyTarget: 300,
        hardCap: 1000,
        pairedAt: Date(),
        sharedSecretFingerprint: ""
    )
}

// MARK: - Pairing Methods
enum PairingMethod {
    case qrCode           // Local — AVFoundation QR scan
    case iMessageLink     // Remote — NSUserActivity Universal Link
}

// MARK: - Pairing Response (Device B → Device A via CloudKit)
/// After Device B scans Device A's QR code and completes its half of the ECDH exchange,
/// it publishes this response to CloudKit. Device A polls for it, consumes the public key,
/// completes its own ECDH exchange, and both devices end up with the same shared secret.
struct PairingResponse {
    let initiatorUserID: String          // Device A's user ID (used as CloudKit record key)
    let responderUserID: String          // Device B's user ID
    let responderDisplayName: String     // Device B's human-readable name
    let responderPublicKey: String       // Base64-encoded P256 ECDH public key (raw representation)
    let goalCurrency: String             // Echoed back from QR payload for contract consistency
    let agreedTarget: Double             // Echoed back from QR payload
    let fingerprint: String              // SHA-256 fingerprint of the derived shared secret
    let createdAt: Date                  // When the response was created
    let expiresAt: Date                  // Response expires after 10 minutes
    var status: String = "pending"       // "pending" → consumed by Device A → deleted

    /// Creates a response with a 10-minute expiry window.
    static func create(
        initiatorUserID: String,
        responderUserID: String,
        responderDisplayName: String,
        responderPublicKey: String,
        goalCurrency: String,
        agreedTarget: Double,
        fingerprint: String
    ) -> PairingResponse {
        PairingResponse(
            initiatorUserID: initiatorUserID,
            responderUserID: responderUserID,
            responderDisplayName: responderDisplayName,
            responderPublicKey: responderPublicKey,
            goalCurrency: goalCurrency,
            agreedTarget: agreedTarget,
            fingerprint: fingerprint,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(600)  // 10-minute TTL
        )
    }
}
