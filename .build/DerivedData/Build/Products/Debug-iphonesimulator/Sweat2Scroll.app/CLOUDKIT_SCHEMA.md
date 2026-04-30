# Sweat2Scroll — CloudKit Schema Reference

Container: `iCloud.com.sweat2scroll`
Dashboard: https://icloud.developer.apple.com

## Automatic Schema Bootstrap

On first launch in a **Debug** build, `CloudKitSchemaBootstrap.initializeIfNeeded()` saves
a seed record of each type to auto-create the schema in the Development environment,
then immediately deletes the seed data. No manual record creation is needed.

After verifying the schema in the Dashboard, click **Deploy Schema to Production**.

---

## Record Types

### 1. AuditEvent

W3C PROV-DM audit log entry. Every policy enforcement action is logged here.

| Field | Type | Encrypted | Indexed | Notes |
|-------|------|-----------|---------|-------|
| `eventType` | String | No | Yes (Queryable, Sortable) | CALORIE_UNLOCK, STEP_UNLOCK, GRACE_PERIOD_GRANTED, BREAK_GLASS_OVERRIDE, TAMPER_HEALTHKIT_REVOKED, TAMPER_SCREENTIME_REVOKED, TAMPER_TIME_DRIFT_DETECTED, SHIELD_ENGAGED, SHIELD_DISENGAGED, SELF_REGULATION_BYPASS |
| `timestamp` | Date/Time | No | Yes (Sortable) | When the event occurred |
| `agentDisplayName` | String | No | No | Human-readable name of the actor |
| `caloriesAtEvent` | Double | **Yes** | — | Active calories at time of event |
| `goalAtEvent` | Double | **Yes** | — | Goal target at time of event |
| `overrideActive` | Int64 | **Yes** | — | Whether a break-glass override was active |
| `jsonLDPayload` | Bytes | **Yes** | — | PROV-O JSON-LD serialization |
| `notes` | String | **Yes** | — | Free-text annotation |

### 2. GovernanceContract

Cryptographic governance contract between two Mutual Controllers.

| Field | Type | Encrypted | Indexed | Notes |
|-------|------|-----------|---------|-------|
| `controlledUserID` | String | No | Yes (Queryable) | Device A's user ID |
| `controllerUserID` | String | No | Yes (Queryable) | Device B's user ID |
| `goalCurrency` | String | No | Yes (Queryable) | "Active Calories" or "Steps" |
| `agreedDailyTarget` | Double | No | No | Daily calorie/step target |
| `hardCap` | Double | No | No | CDC safety cap for age cohort |
| `pairedAt` | Date/Time | No | Yes (Sortable) | When the contract was formed |
| `contractVersion` | String | No | No | Protocol version (currently "1.0") |
| `controlledDisplayName` | String | **Yes** | — | Device A's human-readable name |
| `controllerDisplayName` | String | **Yes** | — | Device B's human-readable name |
| `sharedSecretFingerprint` | String | **Yes** | — | SHA-256 fingerprint of ECDH shared secret |

### 3. PartnerProgress

Real-time fitness progress pushed by each device for partner monitoring.

| Field | Type | Encrypted | Indexed | Notes |
|-------|------|-----------|---------|-------|
| `calories` | Double | No | No | Current active calories today |
| `steps` | Int64 | No | No | Current step count today |
| `goal` | Double | No | No | Today's goal target |
| `currency` | String | No | No | Goal currency ("Active Calories" or "Steps") |
| `lastUpdated` | Date/Time | No | Yes (Sortable) | Last sync timestamp |

Record Name convention: `"myProgress"` for the local device's own record.

### 4. PairingResponse

Ephemeral record for the ECDH pairing handshake (Device B → Device A).

| Field | Type | Encrypted | Indexed | Notes |
|-------|------|-----------|---------|-------|
| `initiatorUserID` | String | No | Yes (Queryable) | Device A's user ID |
| `responderUserID` | String | No | No | Device B's user ID |
| `responderPublicKey` | String | No | No | Base64 P256 ECDH public key |
| `createdAt` | Date/Time | No | No | When the response was created |
| `expiresAt` | Date/Time | No | Yes (Queryable) | 10-minute TTL expiry |
| `status` | String | No | Yes (Queryable) | "pending" → deleted after consumption |
| `responderDisplayName` | String | **Yes** | — | Device B's human-readable name |
| `goalCurrency` | String | **Yes** | — | Echoed from QR payload |
| `agreedTarget` | Double | **Yes** | — | Echoed from QR payload |
| `fingerprint` | String | **Yes** | — | SHA-256 fingerprint of derived secret |

Record Name convention: `"pairing-{initiatorUserID}"` — one active response per initiator.

---

## Subscriptions

### CKQuerySubscription: Partner Progress Updates

Created by `CloudKitService.subscribeToPartnerUpdates()`:

- Record Type: `PartnerProgress`
- Fires on: Record Creation, Record Update
- Notification: Silent push (`shouldSendContentAvailable = true`)
- Purpose: Triggers background fetch when partner's progress changes

---

## Security Model

### Encrypted Fields

All fields stored in `record.encryptedValues` are encrypted using the device owner's
iCloud Keychain. Only the owning iCloud account can decrypt them. This means:

- Health data (calories, goals) is never readable by Apple or any third party
- Display names are encrypted to prevent metadata leakage
- The shared secret fingerprint is encrypted (the actual secret is in the Secure Enclave)

### Access Control

Currently using the **Private Database** for all records. In a future CKShare implementation:

- GovernanceContract records would live in a shared CKRecordZone
- Both paired devices would have read access to each other's zone
- AuditEvent records in the shared zone are readable by the partner
- PartnerProgress records are pushed to the shared zone for real-time monitoring

### Pairing Response TTL

PairingResponse records have a 10-minute expiry. The polling mechanism on Device A
checks `expiresAt` and deletes expired records. If the app crashes mid-pairing,
stale records are cleaned up on the next poll attempt.

---

## Deployment Checklist

1. Run the app on a physical device in Debug mode (first launch bootstraps the schema)
2. Open CloudKit Dashboard → iCloud.com.sweat2scroll → Development
3. Verify all 4 record types exist with the correct fields
4. Add indexes for queryable/sortable fields listed above
5. Click "Deploy Schema to Production"
6. Verify the Production schema matches Development
7. Create a CKQuerySubscription for PartnerProgress in the Dashboard (or let the app create it programmatically)

---

## Troubleshooting

**"CloudKit zone not found"** — The user's iCloud account hasn't created the default
zone yet. This resolves itself on the first record save.

**"User deleted zone"** — The partner deleted their iCloud data. Re-pairing is required.
The app detects this via `CKError.userDeletedZone` and prompts for re-pairing.

**Encrypted fields unreadable** — The user reset their iCloud Keychain. All encrypted
fields become permanently inaccessible. The app must detect this and re-initiate pairing
to create a new contract with a fresh shared secret.
