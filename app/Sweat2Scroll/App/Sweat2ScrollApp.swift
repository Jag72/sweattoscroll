// Sweat2ScrollApp.swift
// Entry point. Requests FamilyControls authorization on first launch.
// Injects environment objects for global state.
// Navigation: Landing → Auth → Onboarding → Dashboard

import SwiftUI

@main
struct Sweat2ScrollApp: App {

    @StateObject private var activityVM   = ActivityViewModel()
    @StateObject private var policyVM     = PolicyViewModel()
    @StateObject private var onboardingVM = OnboardingViewModel()
    @StateObject private var partnerVM    = PartnerViewModel()
    @StateObject private var wellnessVM   = WellnessViewModel()
    // AuthManager is a @MainActor singleton — held here so SwiftUI observes changes
    // and the @EnvironmentObject is available throughout the view hierarchy.
    private let authManager = AuthManager.shared

    init() {
        AppLogger.app.info("Application init starting")

        // 0. App Group self-check — write/read a probe value to confirm the
        //    `group.com.sweat2scroll.appblocker` container is honoring the
        //    entitlement. iOS may emit a noisy `cfprefsd ... kCFPreferencesAnyUser`
        //    warning at launch that's cosmetic; this check is the source of
        //    truth. See `AppGroupHealthCheck.swift` header for context.
        AppGroupHealthCheck.run()

        // 1. FamilyControls authorization — must happen before any ManagedSettingsStore call.
        Task { @MainActor in
            ScreenTimeService.shared.refreshAuthorizationStatus()
            if ScreenTimeService.shared.authorizationStatus == .notDetermined {
                await ScreenTimeService.shared.requestAuthorization()
            }
        }

        // 2. Bootstrap CloudKit schema on first launch (DEBUG only, no-op in Release).
        //    Saves seed records for all record types so the schema is visible in the
        //    CloudKit Dashboard. Run on a real device signed in to iCloud, then
        //    deploy the schema to Production from the Dashboard.
        Task { await CloudKitSchemaBootstrap.initializeIfNeeded() }

        // 3. Midnight reset — calorie tally only. Per-app usage limits reset
        //    via DeviceActivityMonitor at midnight (not a global free window).
        DailyResetManager.shared.performMidnightResetIfNeeded()

        // 4. Calorie observer — listens for new HealthKit activeEnergyBurned samples
        //    and posts a notification so the dashboard can react promptly.
        CalorieObserver.shared.startObserving()

        // 5. Solo blocking session — per-app usage state, bypass timers, and
        //    persisted justification note. Touched here so the App Group container
        //    is populated before the OS shield extension reads from it.
        Task { @MainActor in
            BlockingSessionService.shared.passiveTick()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchFlow {
                SplashRouter()
            }
            .environmentObject(activityVM)
            .environmentObject(policyVM)
            .environmentObject(onboardingVM)
            .environmentObject(partnerVM)
            .environmentObject(wellnessVM)
            .environmentObject(ScreenTimeService.shared)
            .environmentObject(authManager)
            .onOpenURL { url in
                // Let the Google Sign-In SDK claim its OAuth redirect first.
                if GoogleAuthService.handleURL(url) { return }
                guard DeepLinkService.isPairingURL(url) else { return }
                AppLogger.deepLink.info("Pairing URL: \(url.absoluteString, privacy: .public)")
                onboardingVM.handleIncomingPairingURL(url)
            }
        }
    }
}

// Note: `RootView` lives in Views–RootView.swift (auth routing).
// Note: Color.limeAccent is defined in SwiftExtensions.swift
// Note: UserProfile is defined in Models/UserProfile.swift
