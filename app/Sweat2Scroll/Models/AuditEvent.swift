// Models/AuditEvent.swift
// W3C PROV-DM structured audit log entry.
// Every unlock, grace period, break-glass, and tamper event is logged here.
// Serialized to JSON-LD and synced via CloudKit CKShare encrypted fields.

import Foundation

enum AuditEventType: String, Codable {
    case calorieUnlock      = "CALORIE_UNLOCK"
    case stepUnlock         = "STEP_UNLOCK"
    case gracePeriod        = "GRACE_PERIOD_GRANTED"
    case breakGlass         = "BREAK_GLASS_OVERRIDE"
    case tamperHealthKit    = "TAMPER_HEALTHKIT_REVOKED"
    case tamperScreenTime   = "TAMPER_SCREENTIME_REVOKED"
    case timeDrift          = "TAMPER_TIME_DRIFT_DETECTED"
    case shieldEngaged      = "SHIELD_ENGAGED"
    case shieldDisengaged   = "SHIELD_DISENGAGED"
    case selfRegBypass      = "SELF_REGULATION_BYPASS"
}

// MARK: - PROV-DM Audit Event
// Maps to W3C PROV-O ontology for tamper-evident provenance logging
struct AuditEvent: Codable, Identifiable {
    var id: UUID = UUID()

    // prov:Activity
    var eventType: AuditEventType
    var timestamp: Date
    var durationSeconds: Double?

    // prov:Entity — the resource affected
    var entityID: String          // e.g. "urn:uuid:shield-status"
    var entityState: String       // e.g. "UNLOCKED", "LOCKED", "GRACE_PERIOD"

    // prov:Agent — who caused this
    var agentID: String           // iCloud user record name
    var agentDisplayName: String

    // Context
    var caloriesAtEvent: Double
    var stepsAtEvent: Int
    var goalAtEvent: Double
    var overrideActive: Bool
    var notes: String?

    // CloudKit encryption flag — mark all fields sensitive
    var requiresEncryption: Bool = true

    // JSON-LD serialization for PROV-O compliance
    var jsonLDPayload: [String: Any] {
        return [
            "@context": "https://www.w3.org/ns/prov-context.jsonld",
            "@graph": [
                [
                    "@id": "urn:uuid:activity-\(id.uuidString)",
                    "@type": "Activity",
                    "prov:startedAtTime": ISO8601DateFormatter().string(from: timestamp),
                    "prov:wasAssociatedWith": "urn:uuid:agent-\(agentID)"
                ],
                [
                    "@id": "urn:uuid:entity-\(entityID)",
                    "@type": "Entity",
                    "prov:value": entityState,
                    "prov:wasGeneratedBy": "urn:uuid:activity-\(id.uuidString)",
                    "prov:wasAttributedTo": "urn:uuid:agent-\(agentID)"
                ],
                [
                    "@id": "urn:uuid:agent-\(agentID)",
                    "@type": "Agent",
                    "prov:label": agentDisplayName,
                    "s2s:eventType": eventType.rawValue,
                    "s2s:caloriesAtEvent": caloriesAtEvent,
                    "s2s:goalAtEvent": goalAtEvent,
                    "s2s:overrideActive": overrideActive
                ]
            ]
        ]
    }
}
