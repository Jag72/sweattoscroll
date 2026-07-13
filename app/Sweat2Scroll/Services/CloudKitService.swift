// Services/CloudKitService.swift
// Handles all CloudKit operations:
//   - CKShare for peer-to-peer governance contract sync
//   - Encrypted audit log storage (PROV-DM JSON-LD records)
//   - Silent push notifications for tamper alerts
//   - Partner progress synchronization

import Foundation
import CloudKit

@MainActor
class CloudKitService: ObservableObject {

    // MARK: - Singleton
    static let shared = CloudKitService()

    /// Set once we've already printed the hint about the benign
    /// "Field 'recordName' is not marked queryable" CloudKit error so we
    /// don't spam the console on every dashboard refresh. See
    /// `handleCloudKitError(_:)` for the full explanation.
    private static var loggedRecordNameHint = false

    // MARK: - Published State
    @Published var isSyncing: Bool = false
    @Published var partnerProgress: Double = 0      // Partner's current calorie progress
    @Published var auditLog: [AuditEvent] = []
    @Published var lastSyncError: String?

    // MARK: - CloudKit Containers
    private let container = CKContainer(identifier: "iCloud.com.jagadish.sweat2scroll")
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    // MARK: - Record Types
    private let auditRecordType     = "AuditEvent"
    private let contractRecordType  = "GovernanceContract"
    private let progressRecordType  = "PartnerProgress"
    private let pairingRecordType   = "PairingResponse"
    private let userAccountType   = "UserAccount"
    private let pairCodeType      = "PairCode"
    private let bypassGrantType   = "BypassGrant"

    // MARK: - Save Audit Event (encrypted)
    /// Serializes a PROV-DM AuditEvent to CKRecord with encrypted fields.
    func saveAuditEvent(_ event: AuditEvent) async {
        let recordID = CKRecord.ID(recordName: event.id.uuidString)
        let record = CKRecord(recordType: auditRecordType, recordID: recordID)

        // Standard fields
        record["eventType"]          = event.eventType.rawValue as CKRecordValue
        record["timestamp"]          = event.timestamp as CKRecordValue
        record["agentDisplayName"]   = event.agentDisplayName as CKRecordValue

        // Encrypted sensitive fields — Apple encrypts via iCloud Keychain
        // Only the owning iCloud account can decrypt these
        record.encryptedValues["caloriesAtEvent"]  = event.caloriesAtEvent as CKRecordValue
        record.encryptedValues["goalAtEvent"]      = event.goalAtEvent as CKRecordValue
        record.encryptedValues["overrideActive"]   = event.overrideActive as CKRecordValue
        record.encryptedValues["jsonLDPayload"]    = try? JSONSerialization.data(withJSONObject: event.jsonLDPayload) as? CKRecordValue
        record.encryptedValues["notes"]            = (event.notes ?? "") as CKRecordValue

        do {
            try await privateDB.save(record)
            auditLog.append(event)
            print("[CloudKit] Audit event saved: \(event.eventType.rawValue)")
        } catch {
            handleCloudKitError(error)
        }
    }

    // MARK: - Sync Partner Progress
    /// Pushes current calorie progress to the CKShare zone visible to partner.
    /// Uses `upsert(...)` because the recordName is deterministic (`"myProgress"`)
    /// — saving a fresh `CKRecord` would fail with `.serverRecordChanged` /
    /// "record to insert already exists" on every call after the first.
    func syncMyProgress(calories: Double, steps: Int, goal: ActivityGoal) async {
        let recordID = CKRecord.ID(recordName: "myProgress")
        do {
            try await upsert(recordID: recordID, recordType: progressRecordType) { record in
                record["calories"]    = calories as CKRecordValue
                record["steps"]       = steps as CKRecordValue
                record["goal"]        = goal.agreedTarget as CKRecordValue
                record["currency"]    = goal.currency.rawValue as CKRecordValue
                record["lastUpdated"] = Date() as CKRecordValue
            }
        } catch {
            handleCloudKitError(error)
        }
    }

    // MARK: - Send Tamper Alert to Partner
    /// Saves the tamper audit event and ensures the partner's device receives
    /// a silent push via CKDatabaseSubscription (set up once at pairing time).
    func sendTamperAlert(event: AuditEvent) async {
        await saveAuditEvent(event)
        // The CKQuerySubscription registered in setupTamperAlertSubscription() fires
        // on the partner's device whenever a new AuditEvent of type tamper is saved.
        // No additional work is needed here — the subscription drives the push.
        print("[CloudKit] Tamper alert dispatched for: \(event.eventType.rawValue)")
    }

    // MARK: - Tamper Alert Subscription (call once after pairing completes)
    /// Registers a CKQuerySubscription so the partner device receives a silent push
    /// whenever a new AuditEvent with a tamper-type eventType is written to CloudKit.
    /// Idempotent — CloudKit returns a duplicate-subscription error if already registered,
    /// which we silently swallow.
    func setupTamperAlertSubscription() async {
        // Match only tamper-category event types
        let tamperTypes: [AuditEventType] = [.tamperHealthKit, .tamperScreenTime, .timeDrift]
        let tamperValues = tamperTypes.map { $0.rawValue }
        let predicate = NSPredicate(format: "eventType IN %@", tamperValues)

        let subscription = CKQuerySubscription(
            recordType: auditRecordType,
            predicate: predicate,
            subscriptionID: "tamper-alert-subscription",
            options: [.firesOnRecordCreation]
        )

        // Silent push — wakes the partner's app in the background to re-engage shields
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // silent push
        notificationInfo.shouldBadge = false
        subscription.notificationInfo = notificationInfo

        do {
            try await privateDB.save(subscription)
            print("[CloudKit] Tamper alert subscription registered.")
        } catch let error as CKError {
            // .serverRejectedRequest with "duplicate subscription" is expected if already set up
            if error.code == .serverRejectedRequest || error.code == .internalError {
                print("[CloudKit] Tamper alert subscription already exists — skipping.")
            } else {
                handleCloudKitError(error)
            }
        } catch {
            handleCloudKitError(error)
        }
    }

    // MARK: - Fetch Audit Log
    func fetchAuditLog() async {
        let query = CKQuery(recordType: auditRecordType, predicate: NSPredicate(value: true))
        // See `loadContract` — sort by `creationDate` (always-sortable system
        // field) so we don't depend on `timestamp` being marked sortable in
        // CloudKit Dashboard. For audit events, save-order matches event-order
        // closely enough that this is semantically equivalent.
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        do {
            let (results, _) = try await privateDB.records(matching: query)
            auditLog = results.compactMap { _, result in
                guard let record = try? result.get() else { return nil }
                return parseAuditRecord(record)
            }
        } catch {
            handleCloudKitError(error)
        }
    }

    // MARK: - Subscribe to Partner Updates (CKDatabaseSubscription)
    func subscribeToPartnerUpdates() async {
        let subscription = CKQuerySubscription(
            recordType: progressRecordType,
            predicate: NSPredicate(value: true),
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent push
        subscription.notificationInfo = notificationInfo

        do {
            try await privateDB.save(subscription)
            print("[CloudKit] Subscribed to partner progress updates.")
        } catch {
            handleCloudKitError(error)
        }
    }

    // MARK: - Pairing Response Flow (Device B → Device A via CloudKit)

    /// Device B calls this after scanning Device A's QR code and completing its side of the ECDH exchange.
    /// Publishes the response (Device B's public key + metadata) to CloudKit so Device A can poll for it.
    /// `upsert` is required because the recordName is derived deterministically
    /// from the initiator's user ID; a retried call (or a re-pair attempt)
    /// would otherwise fail with `.serverRecordChanged`.
    func sendPairingResponse(_ response: PairingResponse) async throws {
        let recordID = CKRecord.ID(recordName: "pairing-\(response.initiatorUserID)")
        try await upsert(recordID: recordID, recordType: pairingRecordType) { record in
            record["initiatorUserID"]   = response.initiatorUserID as CKRecordValue
            record["responderUserID"]   = response.responderUserID as CKRecordValue
            record["responderPublicKey"] = response.responderPublicKey as CKRecordValue
            record["createdAt"]         = response.createdAt as CKRecordValue
            record["expiresAt"]         = response.expiresAt as CKRecordValue
            record["status"]            = response.status as CKRecordValue

            // Encrypted fields — only the paired iCloud accounts can read these
            record.encryptedValues["responderDisplayName"] = response.responderDisplayName as CKRecordValue
            record.encryptedValues["goalCurrency"]    = response.goalCurrency as CKRecordValue
            record.encryptedValues["agreedTarget"]    = response.agreedTarget as CKRecordValue
            record.encryptedValues["fingerprint"]     = response.fingerprint as CKRecordValue
        }
        print("[CloudKit] Pairing response sent for initiator: \(response.initiatorUserID)")
    }

    /// Device A polls this to check if Device B has responded to the pairing request.
    /// Returns the response if found and not expired, nil otherwise.
    func pollForPairingResponse(initiatorUserID: String) async -> PairingResponse? {
        let recordID = CKRecord.ID(recordName: "pairing-\(initiatorUserID)")

        do {
            let record = try await privateDB.record(for: recordID)

            // Check expiry
            if let expiresAt = record["expiresAt"] as? Date, expiresAt < Date() {
                // Expired — clean up
                try? await privateDB.deleteRecord(withID: recordID)
                return nil
            }

            guard let status = record["status"] as? String, status == "pending" else {
                return nil
            }

            let response = PairingResponse(
                initiatorUserID:     record["initiatorUserID"] as? String ?? "",
                responderUserID:     record["responderUserID"] as? String ?? "",
                responderDisplayName: record.encryptedValues["responderDisplayName"] as? String ?? "",
                responderPublicKey:  record["responderPublicKey"] as? String ?? "",
                goalCurrency:        record.encryptedValues["goalCurrency"] as? String ?? "",
                agreedTarget:        record.encryptedValues["agreedTarget"] as? Double ?? 0,
                fingerprint:         record.encryptedValues["fingerprint"] as? String ?? "",
                createdAt:           record["createdAt"] as? Date ?? Date(),
                expiresAt:           record["expiresAt"] as? Date ?? Date()
            )

            return response
        } catch {
            // CKError.unknownItem means no response yet — that's normal
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                return nil
            }
            handleCloudKitError(error)
            return nil
        }
    }

    /// Device A calls this after successfully consuming the pairing response to clean up.
    func deletePairingResponse(initiatorUserID: String) async {
        let recordID = CKRecord.ID(recordName: "pairing-\(initiatorUserID)")
        do {
            try await privateDB.deleteRecord(withID: recordID)
            print("[CloudKit] Pairing response cleaned up for: \(initiatorUserID)")
        } catch {
            // Non-critical — record may already be gone
            print("[CloudKit] Cleanup warning: \(error.localizedDescription)")
        }
    }

    // MARK: - Fetch Partner Progress from Shared Zone
    /// Queries the partner's most recent PartnerProgress record.
    /// Returns (calories, steps, goal, currency, lastUpdated) or nil if not available.
    ///
    /// **Why we don't predicate on `recordID`:** CloudKit's metadata field
    /// `recordName` is not queryable by default — predicates against it raise
    /// `<CKError ... "Field 'recordName' is not marked queryable">`. We sort
    /// by `lastUpdated` (which IS queryable as a normal CKRecord field), pull
    /// a small window, and skip our own record client-side.
    ///
    /// In the full CKShare implementation this would target the shared zone
    /// directly; today the partner's device writes into our `privateDB` via
    /// a shared `CKRecordZone`, so the only "other" record present here is
    /// the partner's `myProgress` mirror.
    func fetchPartnerProgress() async -> (calories: Double, steps: Int, goal: Double, currency: String, lastUpdated: Date)? {
        let query = CKQuery(
            recordType: progressRecordType,
            predicate: NSPredicate(value: true)
        )
        // See `loadContract` for why `creationDate` is preferred over a
        // user-defined sort key here. We re-derive `lastUpdated` from the
        // record body before returning, so the API contract is unchanged.
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        do {
            // Fetch a couple of recent records so we can skip our own and
            // still return the partner's freshest update.
            let (results, _) = try await privateDB.records(matching: query, resultsLimit: 5)
            for (recordID, result) in results {
                guard recordID.recordName != "myProgress",
                      let record = try? result.get() else { continue }

                let calories    = record["calories"] as? Double ?? 0
                let steps       = record["steps"] as? Int ?? 0
                let goal        = record["goal"] as? Double ?? 300
                let currency    = record["currency"] as? String ?? "Active Calories"
                let lastUpdated = record["lastUpdated"] as? Date ?? Date.distantPast

                return (calories, steps, goal, currency, lastUpdated)
            }
            return nil
        } catch {
            handleCloudKitError(error)
            return nil
        }
    }

    // MARK: - Save Governance Contract
    func saveContract(_ contract: GovernanceContract) async {
        let recordID = CKRecord.ID(recordName: contract.id.uuidString)
        let record = CKRecord(recordType: contractRecordType, recordID: recordID)

        record["controlledUserID"]      = contract.controlledUserID as CKRecordValue
        record["controllerUserID"]      = contract.controllerUserID as CKRecordValue
        record["goalCurrency"]          = contract.goalCurrency.rawValue as CKRecordValue
        record["agreedDailyTarget"]     = contract.agreedDailyTarget as CKRecordValue
        record["hardCap"]               = contract.hardCap as CKRecordValue
        record["pairedAt"]              = contract.pairedAt as CKRecordValue
        record["contractVersion"]       = contract.contractVersion as CKRecordValue

        // Encrypted fields — only the two paired iCloud accounts can read these
        record.encryptedValues["controlledDisplayName"]  = contract.controlledDisplayName as CKRecordValue
        record.encryptedValues["controllerDisplayName"]  = contract.controllerDisplayName as CKRecordValue
        record.encryptedValues["sharedSecretFingerprint"] = contract.sharedSecretFingerprint as CKRecordValue

        do {
            try await privateDB.save(record)
            print("[CloudKit] Contract saved: \(contract.id)")
        } catch {
            handleCloudKitError(error)
        }
    }

    // MARK: - Load Governance Contract
    func loadContract() async -> GovernanceContract? {
        let query = CKQuery(recordType: contractRecordType, predicate: NSPredicate(value: true))
        // Sort by `creationDate` — a CloudKit-managed system field that is
        // always sortable without any Dashboard configuration. We deliberately
        // do NOT sort by the user-defined `pairedAt` here: although our
        // schema-bootstrap comment marks it "indexed, sortable", CloudKit
        // auto-creates user fields as queryable-only on first save. When the
        // requested sort key isn't sortable, CloudKit falls back to sorting
        // by `recordName` and surfaces this as
        // `<CKError ... "Field 'recordName' is not marked queryable">`,
        // visible in production logs on every launch via
        // `RootView.task → PartnerViewModel.loadPersistedState`. Sorting by
        // `creationDate` sidesteps that path entirely. There is at most one
        // contract per user today, so the sort key choice doesn't matter for
        // results.
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        do {
            let (results, _) = try await privateDB.records(matching: query, resultsLimit: 1)
            guard let (_, result) = results.first,
                  let record = try? result.get() else {
                return nil
            }

            let controlledName  = record.encryptedValues["controlledDisplayName"] as? String ?? ""
            let controllerName  = record.encryptedValues["controllerDisplayName"] as? String ?? ""
            let fingerprint     = record.encryptedValues["sharedSecretFingerprint"] as? String ?? ""

            return GovernanceContract(
                controlledUserID: record["controlledUserID"] as? String ?? "",
                controlledDisplayName: controlledName,
                controllerUserID: record["controllerUserID"] as? String ?? "",
                controllerDisplayName: controllerName,
                goalCurrency: GoalCurrency(rawValue: record["goalCurrency"] as? String ?? "Active Calories") ?? .activeCalories,
                agreedDailyTarget: record["agreedDailyTarget"] as? Double ?? 300,
                hardCap: record["hardCap"] as? Double ?? 1000,
                pairedAt: record["pairedAt"] as? Date ?? Date(),
                sharedSecretFingerprint: fingerprint
            )
        } catch {
            handleCloudKitError(error)
            return nil
        }
    }

    // MARK: - Handle Encrypted Key Reset Error
    // If user resets iCloud Keychain, CloudKit encrypted fields become inaccessible.
    // Must detect and re-initiate pairing.
    private func handleCloudKitError(_ error: Error) {
        if let ckError = error as? CKError {
            // Suppress the "Field 'recordName' is not marked queryable"
            // benign error. It fires when a CKQuery against a record type
            // whose user-defined sort fields aren't promoted to sortable in
            // CloudKit Dashboard — at which point CloudKit falls back to
            // sorting by recordName, which is also non-queryable, and the
            // whole query fails. From the app's perspective this means
            // "no data yet" for an empty/unindexed record type, which the
            // callers (loadContract, fetchAuditLog, fetchPartnerProgress,
            // fetchBypassGrant) already handle by returning nil/empty.
            // We log it once per launch as a developer hint without spamming.
            let msg = ckError.localizedDescription.lowercased()
            if ckError.code == .invalidArguments,
               msg.contains("recordname"),
               msg.contains("not marked queryable") {
                if !Self.loggedRecordNameHint {
                    Self.loggedRecordNameHint = true
                    print("[CloudKit] Note: a CKQuery hit an empty/unindexed record type. Treating as no-data. To eliminate this hint, mark the relevant fields Sortable in CloudKit Dashboard for the affected record types.")
                }
                return
            }

            switch ckError.code {
            case .zoneNotFound:
                lastSyncError = "CloudKit zone not found. Re-pairing required."
            case .userDeletedZone:
                lastSyncError = "Partner deleted the shared zone. Please re-pair."
            case .quotaExceeded:
                // Private-DB writes count against the signed-in iCloud account's
                // storage. Common on the Simulator's sandbox account. Local data
                // is unaffected — we just couldn't mirror to iCloud right now.
                lastSyncError = "iCloud storage is full for this account, so we couldn't sync to iCloud. Your data is saved on this device."
            case .notAuthenticated:
                lastSyncError = "Sign in to iCloud (Settings) to sync your account across devices."
            default:
                lastSyncError = ckError.localizedDescription
            }
        }
        print("[CloudKit] Error: \(error)")
    }

    // MARK: - Parse CKRecord → AuditEvent
    private func parseAuditRecord(_ record: CKRecord) -> AuditEvent? {
        guard
            let typeRaw = record["eventType"] as? String,
            let type = AuditEventType(rawValue: typeRaw),
            let timestamp = record["timestamp"] as? Date,
            let agentName = record["agentDisplayName"] as? String
        else { return nil }

        let calories = record.encryptedValues["caloriesAtEvent"] as? Double ?? 0
        let goal     = record.encryptedValues["goalAtEvent"] as? Double ?? 0
        let override = record.encryptedValues["overrideActive"] as? Bool ?? false

        return AuditEvent(
            eventType: type,
            timestamp: timestamp,
            entityID: record.recordID.recordName,
            entityState: type.rawValue,
            agentID: "",
            agentDisplayName: agentName,
            caloriesAtEvent: calories,
            stepsAtEvent: 0,
            goalAtEvent: goal,
            overrideActive: override
        )
    }

    // MARK: - UserAccount (Sign in with Apple profile)

    /// Upsert a user account record via the shared `upsert(...)` helper, so a
    /// re-registration (or any deterministic-recordName path) updates in place
    /// instead of failing with `.serverRecordChanged` / "record to insert
    /// already exists".
    func saveUserAccount(_ account: CloudUserAccount) async throws {
        let recordID = CKRecord.ID(recordName: account.appleUserID)
        try await upsert(recordID: recordID, recordType: userAccountType) { record in
            self.applyAccountFields(account, to: record)
        }
    }

    // MARK: - Upsert primitive
    /// Fetch-or-create + save with one `.serverRecordChanged` retry. Use this
    /// for any record whose `CKRecord.ID` is **deterministic** (i.e. the same
    /// logical entity is saved repeatedly under the same recordName) — the
    /// first save would succeed, but a second naive `database.save(_:)` on a
    /// freshly-built CKRecord is treated as an INSERT by CloudKit and rejected
    /// with `serverRecordChanged` (server message: "record to insert already
    /// exists") because the etag is missing. The classic offending log line:
    ///
    ///   <CKError ... "Server Record Changed" (14/2004); server message =
    ///   "record to insert already exists"; serverEtag = mom2go9h ...>
    ///
    /// `apply` runs against the live record (existing or freshly created)
    /// before the save, so callers don't need to know which path was taken.
    private func upsert(recordID: CKRecord.ID,
                        recordType: String,
                        apply: (CKRecord) -> Void) async throws {
        let record: CKRecord
        if let existing = try? await privateDB.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        apply(record)
        do {
            try await privateDB.save(record)
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            // Conflict: another writer beat us between the fetch and the save.
            // Re-fetch, re-apply, retry once. If that also fails we give up
            // and throw — the caller can decide whether to surface or swallow.
            guard let latest = try? await privateDB.record(for: recordID) else {
                throw ckError
            }
            apply(latest)
            try await privateDB.save(latest)
        }
    }

    private func applyAccountFields(_ account: CloudUserAccount, to record: CKRecord) {
        record["appleUserID"] = account.appleUserID as CKRecordValue
        record["displayName"] = account.displayName as CKRecordValue
        record["appMode"] = (account.appMode?.rawValue ?? "") as CKRecordValue
        record["linkedPeerAppleUserID"] = (account.linkedPeerAppleUserID ?? "") as CKRecordValue
        record["isPaired"] = (account.isPaired ? 1 : 0) as CKRecordValue
        record["relationshipLabel"] = (account.relationshipLabel ?? "") as CKRecordValue
        if let v = account.dailyTargetKcal {
            record["dailyTargetKcal"] = v as CKRecordValue
        } else {
            record["dailyTargetKcal"] = nil
        }
        if let w = account.weightKg {
            record["weightKg"] = w as CKRecordValue
        } else {
            record["weightKg"] = nil
        }
        if let a = account.ageYears {
            record["ageYears"] = a as CKRecordValue
        } else {
            record["ageYears"] = nil
        }
        record["partnershipRole"] = (account.partnershipRole?.rawValue ?? "") as CKRecordValue
        record["email"] = (account.email ?? "") as CKRecordValue
        record["phone"] = (account.phone ?? "") as CKRecordValue
    }

    func fetchUserAccount(appleUserID: String) async -> CloudUserAccount? {
        let recordID = CKRecord.ID(recordName: appleUserID)
        do {
            let record = try await privateDB.record(for: recordID)
            return Self.parseUserAccount(record)
        } catch let e as CKError where e.code == .unknownItem {
            return nil
        } catch {
            handleCloudKitError(error)
            return nil
        }
    }

    /// Strict variant: returns `nil` **only** when the record genuinely does not
    /// exist on the server (`CKError.unknownItem`). Any other failure — network
    /// drop, throttling, iCloud signed out, server outage — is rethrown so the
    /// caller can refuse to clobber the existing CloudKit copy with an empty
    /// fallback. Use this anywhere a `nil` from `fetchUserAccount` would
    /// trigger a destructive write.
    func fetchUserAccountStrict(appleUserID: String) async throws -> CloudUserAccount? {
        let recordID = CKRecord.ID(recordName: appleUserID)
        do {
            let record = try await privateDB.record(for: recordID)
            return Self.parseUserAccount(record)
        } catch let e as CKError where e.code == .unknownItem {
            return nil
        }
    }

    static func parseUserAccount(_ record: CKRecord) -> CloudUserAccount? {
        guard
            let apple = record["appleUserID"] as? String,
            let name = record["displayName"] as? String
        else { return nil }
        let modeRaw = record["appMode"] as? String ?? ""
        let mode: AppMode? = modeRaw.isEmpty ? nil : AppMode(rawValue: modeRaw)
        let peer = record["linkedPeerAppleUserID"] as? String
        let linked = (peer?.isEmpty == false) ? peer : nil
        let paired = (record["isPaired"] as? Int64 ?? 0) != 0
        let rel = record["relationshipLabel"] as? String
        let relClean = (rel?.isEmpty == false) ? rel : nil
        let kcal = record["dailyTargetKcal"] as? Double
        let w = record["weightKg"] as? Double
        let age = record["ageYears"] as? Int
        let roleRaw = record["partnershipRole"] as? String ?? ""
        let role: PartnershipRole? = roleRaw.isEmpty ? nil : PartnershipRole(rawValue: roleRaw)
        let emailRaw = record["email"] as? String ?? ""
        let phoneRaw = record["phone"] as? String ?? ""
        return CloudUserAccount(
            appleUserID: apple,
            displayName: name,
            appMode: mode,
            linkedPeerAppleUserID: linked,
            isPaired: paired,
            relationshipLabel: relClean,
            dailyTargetKcal: kcal,
            weightKg: w,
            ageYears: age,
            partnershipRole: role,
            email: emailRaw.isEmpty ? nil : emailRaw,
            phone: phoneRaw.isEmpty ? nil : phoneRaw
        )
    }

    // MARK: - PairCode lookup (exact code string → record)
    func fetchPairCodeRecord(code: String) async -> CKRecord? {
        let predicate = NSPredicate(format: "code == %@", code)
        let query = CKQuery(recordType: pairCodeType, predicate: predicate)
        do {
            let (results, _) = try await privateDB.records(matching: query, resultsLimit: 1)
            guard let (_, result) = results.first,
                  let record = try? result.get() else { return nil }
            return record
        } catch {
            handleCloudKitError(error)
            return nil
        }
    }

    func savePairCodeRecord(code: String, monitorAppleUserID: String, expiresAt: Date) async throws {
        // Deterministic recordName (`pair-<code>`) — re-emitting the same code
        // (e.g. on a network retry) must update, not insert.
        let recordID = CKRecord.ID(recordName: "pair-\(code)")
        try await upsert(recordID: recordID, recordType: pairCodeType) { record in
            record["code"] = code as CKRecordValue
            record["monitorAppleUserID"] = monitorAppleUserID as CKRecordValue
            record["createdAt"] = Date() as CKRecordValue
            record["expiresAt"] = expiresAt as CKRecordValue
            record["consumed"] = 0 as CKRecordValue
        }
    }

    func deletePairCodeRecord(recordID: CKRecord.ID) async {
        try? await privateDB.deleteRecord(withID: recordID)
    }

    // MARK: - BypassGrant (Emergency Override OTP from partner)
    /// Persists a partner-issued override grant. Other side queries by 6-digit
    /// `code` + `partnershipID` and applies it via ScreenTimeService.
    func saveBypassGrant(_ grant: EmergencyOverrideGrant) async throws {
        let recordID = CKRecord.ID(recordName: grant.id.uuidString)
        let record = CKRecord(recordType: bypassGrantType, recordID: recordID)
        record["code"]              = grant.code as CKRecordValue
        record["partnershipID"]     = grant.partnershipID as CKRecordValue
        record["granterUserID"]     = grant.granterUserID as CKRecordValue
        record["recipientUserID"]   = grant.recipientUserID as CKRecordValue
        record["durationMinutes"]   = grant.durationMinutes as CKRecordValue
        record["createdAt"]         = grant.createdAt as CKRecordValue
        record["expiresAt"]         = grant.expiresAt as CKRecordValue
        record["consumed"]          = 0 as CKRecordValue
        record.encryptedValues["granterDisplayName"] = grant.granterDisplayName as CKRecordValue
        if let r = grant.reason {
            record.encryptedValues["reason"] = r as CKRecordValue
        }
        try await privateDB.save(record)
    }

    /// Returns the freshest unconsumed grant for the given 6-digit code and
    /// partnership scope (or nil if missing / consumed).
    func fetchBypassGrant(code: String, partnershipID: String) async -> EmergencyOverrideGrant? {
        let predicate = NSPredicate(
            format: "code == %@ AND partnershipID == %@ AND consumed == 0",
            code, partnershipID
        )
        let query = CKQuery(recordType: bypassGrantType, predicate: predicate)
        // See `loadContract` — `creationDate` is the always-sortable system
        // metadata field. For bypass grants, save order matches grant-issued
        // order. The compound predicate above narrows results enough that the
        // sort tiebreak almost never matters in practice.
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        do {
            let (results, _) = try await privateDB.records(matching: query, resultsLimit: 1)
            guard let (_, result) = results.first,
                  let record = try? result.get() else { return nil }
            return Self.parseBypassGrant(record)
        } catch {
            handleCloudKitError(error)
            return nil
        }
    }

    /// Marks a grant as consumed (and best-effort deletes it). Idempotent.
    func consumeBypassGrant(recordName: String) async {
        let recordID = CKRecord.ID(recordName: recordName)
        try? await privateDB.deleteRecord(withID: recordID)
    }

    private static func parseBypassGrant(_ record: CKRecord) -> EmergencyOverrideGrant? {
        guard
            let code = record["code"] as? String,
            let pairID = record["partnershipID"] as? String,
            let granter = record["granterUserID"] as? String,
            let recipient = record["recipientUserID"] as? String,
            let durationRaw = record["durationMinutes"] as? Int64,
            let createdAt = record["createdAt"] as? Date,
            let expiresAt = record["expiresAt"] as? Date,
            let id = UUID(uuidString: record.recordID.recordName)
        else { return nil }
        let granterName = record.encryptedValues["granterDisplayName"] as? String ?? "Partner"
        let reason = record.encryptedValues["reason"] as? String
        return EmergencyOverrideGrant(
            id: id,
            code: code,
            partnershipID: pairID,
            granterUserID: granter,
            granterDisplayName: granterName,
            recipientUserID: recipient,
            durationMinutes: Int(durationRaw),
            reason: reason,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }
}
