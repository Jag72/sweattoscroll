// ShieldConfigurationExtension/Sweat2ScrollShieldConfiguration.swift
// Runs in a separate sandboxed process. Customizes the OS-level shield
// overlay shown when a Sweat2Scroll-locked app is launched.
//
// Reads `BlockingSessionService` state from the shared App Group container
// and renders contextual copy:
//   • Grace window     → "Free scroll window — X min left"
//   • Blocked          → "Sweat2Scroll — X kcal to earn your scroll"
//   • 15-min bypass    → "Bypass active — X min left"
//   • Day bypass       → "Day bypass active"

import Foundation
import ManagedSettingsUI
import ManagedSettings
import DeviceActivity
import UIKit

class Sweat2ScrollShieldConfiguration: ShieldConfigurationDataSource {

    // MARK: - Shared App Group
    private let appGroupID = "group.com.sweat2scroll.appblocker"
    private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    // MARK: - App Group Keys (mirrors AppGroupKey enum from main app)
    private enum K {
        static let currentCalories        = "currentCalories"
        static let currentGoal            = "currentGoal"
        static let goalCurrency           = "goalCurrency"
        static let blockingPhase          = "blockingSession.phase"
        static let blockingNote           = "blockingSession.note"
        static let blockingGraceEndsAt    = "blockingSession.graceEndsAt"
        static let blockingBypass15EndsAt = "blockingSession.bypass15EndsAt"
    }

    // MARK: - Shield Configuration entry points
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return buildShieldConfiguration()
    }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return buildShieldConfiguration()
    }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return buildShieldConfiguration()
    }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return buildShieldConfiguration()
    }

    // MARK: - Build Dynamic Shield
    private func buildShieldConfiguration() -> ShieldConfiguration {
        let calories  = sharedDefaults?.double(forKey: K.currentCalories) ?? 0
        let goal      = sharedDefaults?.double(forKey: K.currentGoal) ?? 300
        let remaining = max(goal - calories, 0)
        // Resolve phase live from timestamps so the shield is correct even if
        // the main app hasn't run recently to update `blockingPhase`.
        let phaseRaw  = resolveLivePhase()

        // Sweat2Scroll palette
        let electricOrange = UIColor(red: 1.0, green: 0.388, blue: 0.129, alpha: 1.0)
        let charcoal       = UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0)
        let inkColor       = UIColor.white

        let copy = phaseCopy(phaseRaw: phaseRaw, remaining: remaining)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: charcoal.withAlphaComponent(0.96),
            icon: UIImage(systemName: "bolt.shield.fill"),
            title: ShieldConfiguration.Label(
                text: copy.title,
                color: electricOrange
            ),
            subtitle: ShieldConfiguration.Label(
                text: copy.subtitle,
                color: inkColor.withAlphaComponent(0.78)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Open Sweat2Scroll",
                color: .white
            ),
            primaryButtonBackgroundColor: electricOrange,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Use 15 minutes",
                color: inkColor.withAlphaComponent(0.85)
            )
        )
    }

    // MARK: - Phase-Aware Copy
    private func phaseCopy(phaseRaw: String, remaining: Double)
        -> (title: String, subtitle: String)
    {
        switch phaseRaw {
        case "grace":
            let minutes = minutesUntil(K.blockingGraceEndsAt)
            return (
                title: "Sweat2Scroll",
                subtitle: "Free window: \(minutes) min before apps lock down."
            )
        case "bypass15":
            let minutes = minutesUntil(K.blockingBypass15EndsAt)
            return (
                title: "Sweat2Scroll",
                subtitle: "Bypass ends in \(minutes) min — apps will re-lock."
            )
        case "dayBypass":
            return (
                title: "Sweat2Scroll",
                subtitle: "Day bypass active. Apps unlock at midnight."
            )
        case "unlocked":
            return (
                title: "You earned it.",
                subtitle: "Goal met — apps are unlocked."
            )
        default:
            // .blocked or unknown → "earn your scroll"
            let kcal = Int(remaining)
            let messages = [
                "\(kcal) kcal to earn your scroll back.",
                "Champions earn their rest. \(kcal) kcal to go.",
                "The scroll can wait. The burn cannot.",
                "\(kcal) kcal between you and your feed.",
                "Mamba mode: \(kcal) kcal away."
            ]
            let pick = messages[max(kcal, 0) % messages.count]
            return (
                title: "Sweat2Scroll",
                subtitle: pick
            )
        }
    }

    private func minutesUntil(_ key: String) -> Int {
        guard let date = sharedDefaults?.object(forKey: key) as? Date else { return 0 }
        let secs = date.timeIntervalSinceNow
        return max(0, Int(ceil(secs / 60)))
    }

    /// Recompute the phase from the persisted timestamps. This is independent
    /// of the cached `blockingPhase` string so the shield stays accurate when
    /// the main app has been suspended.
    private func resolveLivePhase() -> String {
        let now = Date()
        let dayBypass = sharedDefaults?.object(forKey: "blockingSession.dayBypassEndsAt") as? Date
        let bypass15  = sharedDefaults?.object(forKey: K.blockingBypass15EndsAt) as? Date
        let grace     = sharedDefaults?.object(forKey: K.blockingGraceEndsAt) as? Date

        if let end = dayBypass, now < end { return "dayBypass" }
        if let end = bypass15,  now < end { return "bypass15"  }
        if let end = grace,     now < end { return "grace"     }
        return "blocked"
    }
}
