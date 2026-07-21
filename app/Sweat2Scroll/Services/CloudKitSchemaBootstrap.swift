// Services/CloudKitSchemaBootstrap.swift
// One-time schema initializer for CloudKit Development environment.
//
// CloudKit auto-creates record types and field indexes from the first CKRecord
// saved of each type. This utility bootstraps all 4 record types with their full
// field sets so the schema is ready for development and testing.
//
// Usage:
//   - Call `CloudKitSchemaBootstrap.initializeIfNeeded()` once on first launch.
//   - After running on a real device, verify in CloudKit Dashboard:
//     https://icloud.developer.apple.com → iCloud.com.jagadish.sweat2scroll → Development
//   - When schema is correct, use "Deploy to Production" in the Dashboard.
//
// ⚠️ This is a Development-only utility. The seed records are deleted after
//     schema creation to avoid polluting the database.

import Foundation
import CloudKit

enum CloudKitSchemaBootstrap {

    // MARK: - Container & Database
    private static let container = CKContainer(identifier: "iCloud.com.jagadish.sweat2scroll")
    private static var privateDB: CKDatabase { container.privateCloudDatabase }

    // MARK: - UserDefaults key to track if schema has been initialized
    // v3: adds BypassGrant (Break-Glass) — bumping the key re-runs the
    // bootstrap once on devices that completed v2.
    private static let bootstrapKey = "cloudkit_schema_bootstrapped_v3"

    // MARK: - Public Entry Point
    /// Call once on first launch. Idempotent — skips if already bootstrapped.
    static func initializeIfNeeded() async {
        #if DEBUG
        guard !UserDefaults.standard.bool(forKey: bootstrapKey) else {
            print("[CloudKit Schema] Already bootstrapped — skipping.")
            return
        }

        print("[CloudKit Schema] Bootstrapping record types...")

        do {
            // Create all record types in parallel
            async let audit       = bootstrapAuditEvent()
            async let contract    = bootstrapGovernanceContract()
            async let progress    = bootstrapPartnerProgress()
            async let pairing     = bootstrapPairingResponse()
            async let userAccount = bootstrapUserAccount()
            async let pairCode    = bootstrapPairCode()
            async let bypass      = bootstrapBypassGrant()

            let results = await [audit, contract, progress, pairing, userAccount, pairCode, bypass]
            let successCount = results.filter { $0 }.count

            if successCount == results.count {
                UserDefaults.standard.set(true, forKey: bootstrapKey)
                print("[CloudKit Schema] ✅ All record types created successfully.")
                print("[CloudKit Schema] → Open CloudKit Dashboard to verify and deploy to Production.")
            } else {
                print("[CloudKit Schema] ⚠️ \(successCount)/\(results.count) record types created. Check logs above.")
            }
        }
        #else
        // No-op in Release builds
        #endif
    }

    // MARK: - AuditEvent Schema
    //
    // Standard fields:
    //   eventType        : String     (indexed, sortable, queryable)
    //   timestamp        : Date/Time  (indexed, sortable)
    //   agentDisplayName : String
    //
    // Encrypted fields (CKRecord.encryptedValues):
    //   caloriesAtEvent  : Double
    //   goalAtEvent      : Double
    //   overrideActive   : Int64 (Bool)
    //   jsonLDPayload    : Bytes (Data)
    //   notes            : String
    //
    private static func bootstrapAuditEvent() async -> Bool {
        let recordID = CKRecord.ID(recordName: "schema-seed-audit")
        let record = CKRecord(recordType: "AuditEvent", recordID: recordID)

        // Standard fields
        record["eventType"]          = "SCHEMA_SEED" as CKRecordValue
        record["timestamp"]          = Date() as CKRecordValue
        record["agentDisplayName"]   = "SchemaBootstrap" as CKRecordValue

        // Encrypted fields
        record.encryptedValues["caloriesAtEvent"]  = 0.0 as CKRecordValue
        record.encryptedValues["goalAtEvent"]      = 0.0 as CKRecordValue
        record.encryptedValues["overrideActive"]   = false as CKRecordValue
        record.encryptedValues["notes"]            = "" as CKRecordValue

        return await saveAndDelete(record, label: "AuditEvent")
    }

    // MARK: - GovernanceContract Schema
    //
    // Standard fields:
    //   controlledUserID   : String
    //   controllerUserID   : String
    //   goalCurrency       : String    (indexed)
    //   agreedDailyTarget  : Double
    //   hardCap            : Double
    //   pairedAt           : Date/Time (indexed, sortable)
    //   contractVersion    : String
    //
    // Encrypted fields:
    //   controlledDisplayName   : String
    //   controllerDisplayName   : String
    //   sharedSecretFingerprint : String
    //
    private static func bootstrapGovernanceContract() async -> Bool {
        let recordID = CKRecord.ID(recordName: "schema-seed-contract")
        let record = CKRecord(recordType: "GovernanceContract", recordID: recordID)

        // Standard fields
        record["controlledUserID"]  = "seed-user-a" as CKRecordValue
        record["controllerUserID"]  = "seed-user-b" as CKRecordValue
        record["goalCurrency"]      = "Active Calories" as CKRecordValue
        record["agreedDailyTarget"] = 300.0 as CKRecordValue
        record["hardCap"]           = 1000.0 as CKRecordValue
        record["pairedAt"]          = Date() as CKRecordValue
        record["contractVersion"]   = "1.0" as CKRecordValue

        // Encrypted fields
        record.encryptedValues["controlledDisplayName"]  = "SeedUserA" as CKRecordValue
        record.encryptedValues["controllerDisplayName"]  = "SeedUserB" as CKRecordValue
        record.encryptedValues["sharedSecretFingerprint"] = "0000000000000000" as CKRecordValue

        return await saveAndDelete(record, label: "GovernanceContract")
    }

    // MARK: - PartnerProgress Schema
    //
    // Standard fields:
    //   calories    : Double
    //   steps       : Int64
    //   goal        : Double
    //   currency    : String
    //   lastUpdated : Date/Time (indexed, sortable)
    //
    private static func bootstrapPartnerProgress() async -> Bool {
        let recordID = CKRecord.ID(recordName: "schema-seed-progress")
        let record = CKRecord(recordType: "PartnerProgress", recordID: recordID)

        record["calories"]    = 0.0 as CKRecordValue
        record["steps"]       = 0 as CKRecordValue
        record["goal"]        = 300.0 as CKRecordValue
        record["currency"]    = "Active Calories" as CKRecordValue
        record["lastUpdated"] = Date() as CKRecordValue

        return await saveAndDelete(record, label: "PartnerProgress")
    }

    // MARK: - PairingResponse Schema
    //
    // Standard fields:
    //   initiatorUserID    : String   (indexed — used as record name key)
    //   responderUserID    : String
    //   responderPublicKey : String   (Base64 P256 ECDH public key)
    //   createdAt          : Date/Time
    //   expiresAt          : Date/Time (indexed — for TTL cleanup queries)
    //   status             : String   (indexed — "pending" / "consumed")
    //
    // Encrypted fields:
    //   responderDisplayName : String
    //   goalCurrency         : String
    //   agreedTarget         : Double
    //   fingerprint          : String
    //
    private static func bootstrapPairingResponse() async -> Bool {
        let recordID = CKRecord.ID(recordName: "schema-seed-pairing")
        let record = CKRecord(recordType: "PairingResponse", recordID: recordID)

        // Standard fields
        record["initiatorUserID"]   = "seed-initiator" as CKRecordValue
        record["responderUserID"]   = "seed-responder" as CKRecordValue
        record["responderPublicKey"] = "" as CKRecordValue
        record["createdAt"]         = Date() as CKRecordValue
        record["expiresAt"]         = Date().addingTimeInterval(600) as CKRecordValue
        record["status"]            = "seed" as CKRecordValue

        // Encrypted fields
        record.encryptedValues["responderDisplayName"] = "SeedPartner" as CKRecordValue
        record.encryptedValues["goalCurrency"]    = "Active Calories" as CKRecordValue
        record.encryptedValues["agreedTarget"]    = 300.0 as CKRecordValue
        record.encryptedValues["fingerprint"]     = "0000000000000000" as CKRecordValue

        return await saveAndDelete(record, label: "PairingResponse")
    }

    // MARK: - UserAccount (Sign in with Apple + app mode)
    private static func bootstrapUserAccount() async -> Bool {
        let recordID = CKRecord.ID(recordName: "schema-seed-useraccount")
        let record = CKRecord(recordType: "UserAccount", recordID: recordID)
        record["appleUserID"] = "seed" as CKRecordValue
        record["displayName"] = "Seed" as CKRecordValue
        record["appMode"] = "solo" as CKRecordValue
        record["linkedPeerAppleUserID"] = "" as CKRecordValue
        record["isPaired"] = 0 as CKRecordValue
        record["relationshipLabel"] = "" as CKRecordValue
        record["dailyTargetKcal"] = 300.0 as CKRecordValue
        record["weightKg"] = 70.0 as CKRecordValue
        record["ageYears"] = 30 as CKRecordValue
        return await saveAndDelete(record, label: "UserAccount")
    }

    // MARK: - PairCode (6-digit monitor → user pairing)
    private static func bootstrapPairCode() async -> Bool {
        let recordID = CKRecord.ID(recordName: "schema-seed-paircode-000000")
        let record = CKRecord(recordType: "PairCode", recordID: recordID)
        record["code"] = "000000" as CKRecordValue
        record["monitorAppleUserID"] = "seed-monitor" as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["expiresAt"] = Date().addingTimeInterval(600) as CKRecordValue
        record["consumed"] = 1 as CKRecordValue
        return await saveAndDelete(record, label: "PairCode")
    }

    // MARK: - BypassGrant Schema (Break-Glass emergency override)
    // Mirrors CloudKitService.saveBypassGrant exactly — queried by
    // `code == %@ AND partnershipID == %@ AND consumed == 0`.
    private static func bootstrapBypassGrant() async -> Bool {
        let recordID = CKRecord.ID(recordName: "schema-seed-bypassgrant-000000")
        let record = CKRecord(recordType: "BypassGrant", recordID: recordID)
        record["code"]            = "000000" as CKRecordValue
        record["partnershipID"]   = "seed-partnership" as CKRecordValue
        record["granterUserID"]   = "seed-granter" as CKRecordValue
        record["recipientUserID"] = "seed-recipient" as CKRecordValue
        record["durationMinutes"] = 15 as CKRecordValue
        record["createdAt"]       = Date() as CKRecordValue
        record["expiresAt"]       = Date().addingTimeInterval(600) as CKRecordValue
        record["consumed"]        = 1 as CKRecordValue
        record.encryptedValues["granterDisplayName"] = "seed" as CKRecordValue
        record.encryptedValues["reason"]             = "schema seed" as CKRecordValue
        return await saveAndDelete(record, label: "BypassGrant")
    }

    // MARK: - Save then Delete (creates schema without leaving stale data)
    private static func saveAndDelete(_ record: CKRecord, label: String) async -> Bool {
        do {
            // Save — this creates the record type and all its fields in CloudKit
            try await privateDB.save(record)
            print("[CloudKit Schema] ✅ \(label) — record type created")

            // Delete the seed record immediately to keep the DB clean
            try await privateDB.deleteRecord(withID: record.recordID)
            print("[CloudKit Schema]    └─ Seed record cleaned up")

            return true
        } catch let error as CKError {
            if error.code == .serverRecordChanged {
                // Record already exists from a previous partial bootstrap — that's fine
                print("[CloudKit Schema] ⚠️ \(label) — already exists (schema OK)")
                try? await privateDB.deleteRecord(withID: record.recordID)
                return true
            }
            print("[CloudKit Schema] ❌ \(label) — failed: \(error.localizedDescription)")
            return false
        } catch {
            print("[CloudKit Schema] ❌ \(label) — failed: \(error.localizedDescription)")
            return false
        }
    }
}
