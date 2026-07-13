// Auth/AuthManager.swift
// Sign in with Apple + CloudKit UserAccount → `AppAuthState` routing.

import Foundation
import AuthenticationServices

@MainActor
final class AuthManager: ObservableObject {

    static let shared = AuthManager()

    @Published var authState: AppAuthState = .unauthenticated
    @Published var postAuthStep: PostAuthOnboardingStep = .modeSelection
    @Published var isLoadingAuth = false
    @Published var lastAuthError: String?

    @Published var currentAppleUserID: String?
    @Published private(set) var cachedAccount: CloudUserAccount?

    private let appleIDDefaultsKey = "s2s_apple_user_id"
    private let cloud = CloudKitService.shared

    /// True when signed in via the DEBUG dummy login — skips all CloudKit writes.
    var isDevSession: Bool {
        currentAppleUserID?.hasPrefix("dev_") == true
    }

    /// Display name for the current user — used across dashboards.
    var userDisplayName: String {
        let name = cachedAccount?.displayName ?? ""
        return name.isEmpty ? "User" : name
    }

    private init() {
        Task { await restoreSessionIfPossible() }
    }

    // MARK: - Session

    func restoreSessionIfPossible() async {
        guard let id = UserDefaults.standard.string(forKey: appleIDDefaultsKey), !id.isEmpty else {
            authState = .unauthenticated
            currentAppleUserID = nil
            cachedAccount = nil
            return
        }
        currentAppleUserID = id
        await refreshAccountFromCloud(appleUserID: id)
    }

    private func refreshAccountFromCloud(appleUserID: String) async {
        if let account = await cloud.fetchUserAccount(appleUserID: appleUserID) {
            cachedAccount = account
            routeReturningUser(account)
            AppSession.setAuthenticated()
        } else {
            authState = .unauthenticated
            currentAppleUserID = nil
            cachedAccount = nil
        }
    }

    // MARK: - Sign in with Apple

    func handleAppleCredential(_ credential: ASAuthorizationAppleIDCredential) async {
        isLoadingAuth = true
        lastAuthError = nil
        defer { isLoadingAuth = false }

        let id = credential.user
        let parts = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }
        let fromAppleName = parts.joined(separator: " ")
        let emailLocal = credential.email?.split(separator: "@").first.map(String.init)
        let display = !fromAppleName.isEmpty ? fromAppleName : (emailLocal ?? "Athlete")

        UserDefaults.standard.set(id, forKey: appleIDDefaultsKey)
        currentAppleUserID = id

        if var existing = await cloud.fetchUserAccount(appleUserID: id) {
            if existing.displayName.isEmpty { existing.displayName = display }
            if existing.email == nil, let appleEmail = credential.email, !appleEmail.isEmpty {
                existing.email = appleEmail.lowercased()
            }
            cachedAccount = existing
            try? await cloud.saveUserAccount(existing)
            routeReturningUser(existing)
            AppSession.setAuthenticated()
        } else {
            var newAcc = CloudUserAccount.newUser(appleUserID: id, displayName: display)
            if let appleEmail = credential.email, !appleEmail.isEmpty {
                newAcc.email = appleEmail.lowercased()
            }
            // Best-effort cloud mirror — a quota/outage error must not block a
            // brand-new Sign in with Apple from starting onboarding locally.
            try? await cloud.saveUserAccount(newAcc)
            cachedAccount = newAcc
            authState = .onboarding
            postAuthStep = .prdHealth
            AppSession.setAuthenticated()
        }
    }

    // MARK: - Sign in with Google

    /// Establishes a session from a Google profile, mirroring the Apple flow:
    /// returning users route straight to their dashboard; new users start
    /// onboarding. The Google user id is namespaced (`google_…`) so it can't
    /// collide with an Apple user id in CloudKit.
    func handleGoogleSignIn(userID: String, email: String?, fullName: String?) async {
        isLoadingAuth = true
        lastAuthError = nil
        defer { isLoadingAuth = false }

        let id = "google_" + userID
        let emailLocal = email?.split(separator: "@").first.map(String.init)
        let trimmedName = (fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let display = !trimmedName.isEmpty ? trimmedName : (emailLocal ?? "Athlete")

        UserDefaults.standard.set(id, forKey: appleIDDefaultsKey)
        currentAppleUserID = id

        if var existing = await cloud.fetchUserAccount(appleUserID: id) {
            if existing.displayName.isEmpty { existing.displayName = display }
            if existing.email == nil, let email, !email.isEmpty {
                existing.email = email.lowercased()
            }
            cachedAccount = existing
            try? await cloud.saveUserAccount(existing)
            routeReturningUser(existing)
            AppSession.setAuthenticated()
        } else {
            var newAcc = CloudUserAccount.newUser(appleUserID: id, displayName: display)
            if let email, !email.isEmpty { newAcc.email = email.lowercased() }
            // Best-effort cloud mirror — a quota/outage error must not block a
            // brand-new Google sign-in from starting onboarding locally.
            try? await cloud.saveUserAccount(newAcc)
            cachedAccount = newAcc
            authState = .onboarding
            postAuthStep = .prdHealth
            AppSession.setAuthenticated()
        }
    }

    private func routeReturningUser(_ account: CloudUserAccount) {
        applyReturningUserRouting(account)
    }

    /// Maps `CloudUserAccount` → `authState` / `postAuthStep` (session restore, mode switch, refresh).
    private func applyReturningUserRouting(_ account: CloudUserAccount) {
        guard let mode = account.appMode else {
            if UserDefaults.standard.bool(forKey: "onboardingComplete") {
                authState = .solo
                postAuthStep = .modeSelection
            } else {
                authState = .onboarding
                postAuthStep = .prdHealth
            }
            return
        }
        switch mode {
        case .solo:
            let ready = (account.ageYears != nil) && account.dailyTargetKcal != nil
            authState = ready ? .solo : .onboarding
            if !ready { postAuthStep = .soloProfile }
        case .user:
            let ready = account.ageYears != nil && account.dailyTargetKcal != nil
            if !ready {
                authState = .onboarding
                postAuthStep = .userProfile
            } else {
                authState = .user(paired: account.isPaired)
            }
        case .monitor:
            let ready = account.relationshipLabel != nil && !account.relationshipLabel!.isEmpty
            if !ready {
                authState = .onboarding
                postAuthStep = .monitorProfile
            } else {
                authState = .monitor(paired: account.isPaired)
            }
        }
    }

    /// After switching from solo → monitored, `UserDashboardView` opens the pair sheet once on appear.
    private(set) var openPairCodeOnNextUserDashboard: Bool = false

    func consumeOpenPairCodeOnUserDashboard() -> Bool {
        let v = openPairCodeOnNextUserDashboard
        openPairCodeOnNextUserDashboard = false
        return v
    }

    /// Switch primary role (Solo / Monitored / Monitor). Clears pairing when the role actually changes.
    func switchAppMode(_ mode: AppMode) async throws {
        guard var acc = cachedAccount, currentAppleUserID != nil else { return }
        if acc.appMode == mode {
            applyReturningUserRouting(acc)
            return
        }
        let previous = acc.appMode
        acc.appMode = mode
        if previous != mode {
            acc.isPaired = false
            acc.linkedPeerAppleUserID = nil
        }
        if !isDevSession { try await cloud.saveUserAccount(acc) }
        cachedAccount = acc
        applyReturningUserRouting(acc)
    }

    /// Menu: “Pair with a monitor” from solo — become monitored user, then show code entry when the dashboard loads.
    func switchToMonitoredAndShowPairCodeEntry() async throws {
        openPairCodeOnNextUserDashboard = false
        try await switchAppMode(.user)
        if case .user(let paired) = authState, !paired {
            openPairCodeOnNextUserDashboard = true
        }
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: appleIDDefaultsKey)
        currentAppleUserID = nil
        cachedAccount = nil
        authState = .unauthenticated
        postAuthStep = .prdHealth
        AppSession.clear()
    }

    // MARK: - Username / password (local credential store)

    /// Create a brand-new account from the sign-up form. Stores a salted
    /// password hash in the Keychain (keyed by the normalized username) so the
    /// user can sign back in later, then kicks off the same PRD health-first
    /// onboarding used by Sign in with Apple.
    ///
    /// Because the username→ID hash is deterministic, a returning user who wiped
    /// the app and re-signs up resolves to the *same* `appleUserID` and finds
    /// their old CloudKit record. We must not paper over a transient fetch
    /// failure with `newUser(...)` here either — that would overwrite their
    /// real cloud profile with empty fields. On transient errors we throw so
    /// the user can retry; on `.unknownItem` we know it's a true new sign-up.
    func signUp(username: String, password: String, displayName: String? = nil) async throws {
        isLoadingAuth = true
        lastAuthError = nil
        defer { isLoadingAuth = false }

        let key = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let providedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let emailLocal = key.split(separator: "@").first.map(String.init)
        let display = !providedName.isEmpty ? providedName : (emailLocal ?? "Athlete")

        let id = try EmailCredentialStore.register(email: key, password: password)

        // Probe CloudKit *before* claiming this session so a network outage
        // can't trick us into writing a blank fallback over the real record.
        let existing: CloudUserAccount?
        do {
            existing = try await cloud.fetchUserAccountStrict(appleUserID: id)
        } catch {
            lastAuthError = "Couldn't reach iCloud. Check your connection and try again."
            throw error
        }

        UserDefaults.standard.set(id, forKey: appleIDDefaultsKey)
        currentAppleUserID = id

        var account = existing
            ?? CloudUserAccount.newUser(appleUserID: id, displayName: display.isEmpty ? "Athlete" : display)
        if account.displayName.isEmpty { account.displayName = display }
        // Usernames may be plain handles — only email-shaped ones go in the email slot.
        if SignUpView.isValidEmail(key) { account.email = key }
        cachedAccount = account
        try? await cloud.saveUserAccount(account)

        // If we recovered a fully-onboarded existing account, drop the user
        // straight back into their dashboard instead of forcing them through
        // onboarding again.
        if let existing, existing.appMode != nil {
            routeReturningUser(account)
        } else {
            authState = .onboarding
            postAuthStep = .prdHealth
        }
        AppSession.setAuthenticated()
    }

    /// Sign in using a previously-registered username/password on this device.
    ///
    /// Critical safety property: if CloudKit returns *anything* other than a
    /// definitive "no such record" we must **not** persist a blank fallback —
    /// doing so would overwrite the user's real CloudKit account (display
    /// name, calorie goal, partner pairing, role, etc.) with empty defaults
    /// and is unrecoverable on the server side. On transient errors we throw
    /// so the user can retry once their connection recovers.
    func signIn(username: String, password: String) async throws {
        isLoadingAuth = true
        lastAuthError = nil
        defer { isLoadingAuth = false }

        let id = try EmailCredentialStore.verify(email: username, password: password)

        let existing: CloudUserAccount?
        do {
            existing = try await cloud.fetchUserAccountStrict(appleUserID: id)
        } catch {
            // Transient failure — never write a blank fallback over the real
            // server record. Keep the previous session intact and surface the
            // error to the UI so the user can retry.
            lastAuthError = "Couldn't reach iCloud. Check your connection and try again."
            throw error
        }

        // Only after we know iCloud actually reachable do we promote this
        // session as the current user.
        UserDefaults.standard.set(id, forKey: appleIDDefaultsKey)
        currentAppleUserID = id

        if let existing {
            cachedAccount = existing
            routeReturningUser(existing)
            AppSession.setAuthenticated()
            return
        }

        // Genuinely first sign-in on this device with no CloudKit copy yet —
        // safe to seed a new account.
        let display = username.trimmingCharacters(in: .whitespacesAndNewlines)
        var fallback = CloudUserAccount.newUser(appleUserID: id, displayName: display.isEmpty ? "Athlete" : display)
        if SignUpView.isValidEmail(display) { fallback.email = display.lowercased() }
        cachedAccount = fallback
        try? await cloud.saveUserAccount(fallback)
        authState = .onboarding
        postAuthStep = .prdHealth
        AppSession.setAuthenticated()
    }

    // MARK: - Password reset (local credential store)

    enum PasswordResetError: LocalizedError {
        case noLocalAccount

        var errorDescription: String? {
            switch self {
            case .noLocalAccount:
                return "No account with that username exists on this device. If you signed up with Apple, recover from your Apple ID instead."
            }
        }
    }

    /// Reset the locally-stored password for a username registered on this
    /// device. Because the username→ID hash is deterministic, overwriting the
    /// Keychain record keeps the same `appleUserID`, so the user's CloudKit
    /// profile, pairing and role stay linked. The device unlock (Keychain
    /// `WhenUnlockedThisDeviceOnly`) is the trust boundary here; cross-device
    /// recovery is handled by Sign in with Apple.
    func resetLocalPassword(username: String, newPassword: String) throws {
        guard EmailCredentialStore.hasAccount(email: username) else {
            throw PasswordResetError.noLocalAccount
        }
        try EmailCredentialStore.register(email: username, password: newPassword)
    }

    // MARK: - Mode & onboarding

    func completeModeSelection(_ mode: AppMode) async throws {
        guard var acc = cachedAccount, currentAppleUserID != nil else { return }
        acc.appMode = mode
        acc.isPaired = false
        acc.linkedPeerAppleUserID = nil
        if !isDevSession { try await cloud.saveUserAccount(acc) }
        cachedAccount = acc
        switch mode {
        case .solo:    postAuthStep = .soloProfile
        case .user:    postAuthStep = .userProfile
        case .monitor: postAuthStep = .monitorProfile
        }
    }

    func completeSoloOnboarding(displayName: String, ageYears: Int, weightKg: Double, dailyTargetKcal: Double) async throws {
        guard var acc = cachedAccount else { return }
        acc.displayName = displayName
        acc.ageYears = ageYears
        acc.weightKg = weightKg
        acc.dailyTargetKcal = dailyTargetKcal
        acc.appMode = .solo
        if !isDevSession { try await cloud.saveUserAccount(acc) }
        cachedAccount = acc
        authState = .solo
    }

    func completeUserOnboarding(displayName: String, ageYears: Int, weightKg: Double, dailyTargetKcal: Double, skipPairing: Bool) async throws {
        guard var acc = cachedAccount else { return }
        acc.displayName = displayName
        acc.ageYears = ageYears
        acc.weightKg = weightKg
        acc.dailyTargetKcal = dailyTargetKcal
        acc.appMode = .user
        if skipPairing {
            acc.isPaired = false
            acc.linkedPeerAppleUserID = nil
        }
        if !isDevSession { try await cloud.saveUserAccount(acc) }
        cachedAccount = acc
        authState = .user(paired: acc.isPaired)
    }

    func completeMonitorOnboarding(displayName: String, relationship: String) async throws {
        guard var acc = cachedAccount else { return }
        acc.displayName = displayName
        acc.appMode = .monitor
        acc.relationshipLabel = relationship
        acc.isPaired = false
        acc.linkedPeerAppleUserID = nil
        if !isDevSession { try await cloud.saveUserAccount(acc) }
        cachedAccount = acc
        authState = .monitor(paired: false)
    }

    func refreshAfterPairing() async {
        guard let id = currentAppleUserID else { return }
        await refreshAccountFromCloud(appleUserID: id)
    }

    // MARK: - Partnership role (post-pair)

    /// Persist the user's chosen `PartnershipRole` after pairing succeeds. Each
    /// device stores its own role independently — the two sides don't have to
    /// agree (e.g. parent picks `.controller`, child picks `.controlled`).
    func setPartnershipRole(_ role: PartnershipRole) async {
        guard var acc = cachedAccount else { return }
        acc.partnershipRole = role
        cachedAccount = acc
        if !isDevSession {
            try? await cloud.saveUserAccount(acc)
        }
    }

    /// Convenience used by onboarding after pairing — persists the role and
    /// drops the user into their dashboard.
    func finishPostPairingRoleSelection(_ role: PartnershipRole) async {
        await setPartnershipRole(role)
        if currentAppleUserID != nil {
            await refreshAfterPairing()
        }
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }

    // MARK: - PRD v2 onboarding

    func advancePRDOnboarding(to step: PostAuthOnboardingStep) {
        postAuthStep = step
    }

    /// Called from `OnboardingCompleteView` after screens 3A–3F. Sets solo profile + PRD `onboardingComplete`.
    func finishPRDOnboardingFlow(displayName: String, calorieGoal: Double, ageYears: Int?, weightKg: Double?) async throws {
        guard var acc = cachedAccount else { return }
        acc.displayName = displayName
        acc.dailyTargetKcal = calorieGoal
        acc.ageYears = ageYears
        acc.weightKg = weightKg
        acc.appMode = .solo
        acc.isPaired = false
        // Best-effort cloud save: a CloudKit outage, throttle, or storage-quota
        // error must NOT trap the user behind onboarding. We always cache the
        // profile locally and complete the flow; the record re-syncs on the
        // next successful save (mode switch, pairing, next launch).
        if !isDevSession {
            do {
                try await cloud.saveUserAccount(acc)
            } catch {
                print("[Auth] onboarding profile cloud-save deferred: \(error.localizedDescription)")
            }
        }
        cachedAccount = acc
        authState = .solo
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        UserDefaults.standard.set(calorieGoal, forKey: "dailyCalorieGoal")
    }

    func setBreakGlassActive(until expiry: Date) {
        authState = .breakGlassActive(expiresAt: expiry)
    }

    func clearBreakGlass() async {
        await refreshAfterPairing()
    }

    // MARK: - Dev / Dummy Login (DEBUG only)
    // Bypasses Apple Sign In and CloudKit entirely.
    // Injects a fake account and routes straight to ModeSelectionView.
    #if DEBUG
    func devSignIn(as mode: AppMode? = nil) {
        isLoadingAuth = false
        lastAuthError = nil

        let fakeID = "dev_\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(fakeID, forKey: appleIDDefaultsKey)
        currentAppleUserID = fakeID

        var account = CloudUserAccount.newUser(appleUserID: fakeID, displayName: "Dev User")

        if let mode = mode {
            // Jump straight to the right dashboard (skip onboarding)
            account.appMode    = mode
            account.ageYears   = 28
            account.weightKg   = 75
            account.dailyTargetKcal = 400
            account.isPaired   = false
            cachedAccount = account
            switch mode {
            case .solo:    authState = .solo
            case .user:    authState = .user(paired: false)
            case .monitor: authState = .monitor(paired: false)
            }
        } else {
            // Go through PRD health-first onboarding
            cachedAccount = account
            authState = .onboarding
            postAuthStep = .prdHealth
        }
        AppSession.setAuthenticated()
    }
    #endif
}
