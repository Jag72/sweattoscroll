// Models/AppAuthModels.swift
// Auth routing enums and CloudKit-backed user account payload.

import Foundation

// MARK: - App mode (persisted to CloudKit UserAccount)
enum AppMode: String, Codable, CaseIterable {
    case solo
    case user
    case monitor
}

// MARK: - Partnership role (persisted to CloudKit UserAccount once paired)
/// How the two paired devices relate to each other.
/// • `mutual`     → both partners track calories; either can grant emergency overrides.
/// • `controller` → I monitor my partner (e.g., parent). I can issue override OTPs but my
///                  device is not blocked by Sweat2Scroll.
/// • `controlled` → I'm the one being monitored (e.g., child). My apps get blocked; my
///                  partner can grant emergency override OTPs to unlock me.
enum PartnershipRole: String, Codable, CaseIterable {
    case mutual
    case controller
    case controlled

    var displayTitle: String {
        switch self {
        case .mutual:     return "Mutual buddies"
        case .controller: return "I'm the controller"
        case .controlled: return "I'm being monitored"
        }
    }

    var displaySubtitle: String {
        switch self {
        case .mutual:
            return "We both burn calories. Either of us can grant the other an emergency override."
        case .controller:
            return "Like a parent or coach. I'm not blocked — I issue override OTPs to my partner."
        case .controlled:
            return "Like a child or trainee. My apps get blocked; my partner sends an OTP to unlock me."
        }
    }

    /// Can this role generate (issue) override OTPs to the other partner?
    var canGrantOverride: Bool {
        switch self {
        case .mutual, .controller: return true
        case .controlled:          return false
        }
    }

    /// Can this role redeem an OTP from the partner to unlock their own apps?
    var canRedeemOverride: Bool {
        switch self {
        case .mutual, .controlled: return true
        case .controller:          return false
        }
    }
}

// MARK: - Auth state (drives RootView)
enum AppAuthState: Equatable {
    case unauthenticated
    /// New Apple ID sign-in: pick Solo / User / Monitor next.
    case onboarding
    case solo
    case user(paired: Bool)
    case monitor(paired: Bool)
    case breakGlassActive(expiresAt: Date)
}

// MARK: - Which screen to show inside `.onboarding`
enum PostAuthOnboardingStep: Equatable {
    /// Legacy CloudKit mode picker (still used when changing role from menu).
    case modeSelection
    case soloProfile
    case userProfile
    case monitorProfile

    // MARK: PRD v2 — post sign-up flow (new accounts)
    case prdHealth
    case prdManual
    case prdCalorie
    case prdApps
    case prdPairingPrompt
    /// Shown right after pairing succeeds — both partners pick their PartnershipRole.
    case prdRoleSelection
    case prdComplete
}

extension PostAuthOnboardingStep {
    /// Linear order of every PRD-onboarding screen the user can see.
    /// `prdManual` and `prdRoleSelection` are conditional — `prdComplete` is the
    /// celebration page and is intentionally excluded from the progress strip.
    private static func sequence(needsManualBody: Bool,
                                 willShowRoleSelection: Bool) -> [PostAuthOnboardingStep] {
        var s: [PostAuthOnboardingStep] = [.prdHealth]
        if needsManualBody { s.append(.prdManual) }
        s.append(contentsOf: [.prdCalorie, .prdApps, .prdPairingPrompt])
        if willShowRoleSelection { s.append(.prdRoleSelection) }
        return s
    }

    /// Returns `(currentStepIndex, totalSteps)` (both 0-based for the indicator)
    /// so the strip never skips a slot when an optional step is hidden.
    /// Returns `nil` for non-PRD or terminal screens.
    func progressIndicator(needsManualBody: Bool,
                           willShowRoleSelection: Bool) -> (current: Int, total: Int)? {
        let s = Self.sequence(needsManualBody: needsManualBody,
                              willShowRoleSelection: willShowRoleSelection)
        guard let i = s.firstIndex(of: self) else { return nil }
        return (i, s.count)
    }

    /// Previous PRD step in the visible sequence, or `nil` if this is the first
    /// step (or not a PRD step at all).
    func previousStep(needsManualBody: Bool,
                      willShowRoleSelection: Bool) -> PostAuthOnboardingStep? {
        let s = Self.sequence(needsManualBody: needsManualBody,
                              willShowRoleSelection: willShowRoleSelection)
        guard let i = s.firstIndex(of: self), i > 0 else { return nil }
        return s[i - 1]
    }
}

// MARK: - Pairing outcome
enum PairingResult: Equatable {
    case success(linkedMonitorID: String)
    case invalid
    case expired
}

// MARK: - Cloud user account (mirrors CK record `UserAccount`)
struct CloudUserAccount: Codable, Equatable {
    var appleUserID: String
    var displayName: String
    /// `nil` until the user finishes **ModeSelectionView** (stored as empty string in CloudKit).
    var appMode: AppMode?
    /// For user mode: monitor's Apple user ID when paired.
    var linkedPeerAppleUserID: String?
    var isPaired: Bool
    /// Monitor-specific: relationship label.
    var relationshipLabel: String?
    /// Solo/user: daily scroll cap / calorie goal (kcal).
    var dailyTargetKcal: Double?
    var weightKg: Double?
    var ageYears: Int?
    /// Locally-chosen partnership role. `nil` until paired and the user picks a role
    /// from `PartnershipRoleSelectionView`. Each side stores its own choice — the two
    /// devices don't have to agree (parent picks `.controller`, child picks `.controlled`).
    var partnershipRole: PartnershipRole?
    /// Email address captured during email-password sign up or returned by Apple.
    var email: String?
    /// Optional phone collected during email sign up.
    var phone: String?

    static func newUser(appleUserID: String, displayName: String) -> CloudUserAccount {
        CloudUserAccount(
            appleUserID: appleUserID,
            displayName: displayName,
            appMode: nil,
            linkedPeerAppleUserID: nil,
            isPaired: false,
            relationshipLabel: nil,
            dailyTargetKcal: nil,
            weightKg: nil,
            ageYears: nil,
            partnershipRole: nil,
            email: nil,
            phone: nil
        )
    }
}
