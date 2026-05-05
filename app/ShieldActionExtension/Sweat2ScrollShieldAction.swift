// ShieldActionExtension/Sweat2ScrollShieldAction.swift
// Handles button taps on the OS-level Sweat2Scroll shield.
//
//   primary "Open Sweat2Scroll"  → close the shield. iOS sends the user back
//                                  to home; they manually open Sweat2Scroll
//                                  to see their progress / start moving.
//   secondary "Use 15 minutes"   → set `pendingJustify = true` in the App
//                                  Group + close. We deliberately DO NOT drop
//                                  the shield here; the bypass requires a
//                                  written note, which can only happen inside
//                                  the main app's `JustificationNoteSheet`.
//                                  When the user opens Sweat2Scroll, the
//                                  dashboard reads the flag and surfaces the
//                                  sheet automatically.

import Foundation
import ManagedSettingsUI
import ManagedSettings

class Sweat2ScrollShieldAction: ShieldActionDelegate {

    private let appGroupID = "group.com.sweat2scroll.appblocker"
    private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    // Mirrors the main-app AppGroupKey enum (extension can't import main code).
    private enum K {
        static let pendingJustify       = "blockingSession.pendingJustify"
        static let selfRegBypassAt      = "selfRegBypassRequestedAt"
        static let selfRegBypassRequested = "selfRegBypassRequested"
    }

    // MARK: - Application
    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            requestJustificationFromMainApp()
            completionHandler(.close)
        @unknown default:
            completionHandler(.defer)
        }
    }

    // MARK: - Web Domain
    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            requestJustificationFromMainApp()
            completionHandler(.close)
        @unknown default:
            completionHandler(.defer)
        }
    }

    // MARK: - Justification Routing
    /// Mark a pending justification so the main app surfaces the note sheet
    /// the next time it becomes active. The shield itself stays engaged until
    /// the user submits the note (which triggers the actual 15-min bypass).
    private func requestJustificationFromMainApp() {
        sharedDefaults?.set(true, forKey: K.pendingJustify)
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: K.selfRegBypassAt)
        sharedDefaults?.set(true, forKey: K.selfRegBypassRequested)
    }
}
