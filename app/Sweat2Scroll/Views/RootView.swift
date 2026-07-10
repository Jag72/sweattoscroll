// Views/RootView.swift
// Routes by `AuthManager.authState` (Sign in with Apple → mode → dashboards).

import SwiftUI

struct RootView: View {
    @ObservedObject private var auth = AuthManager.shared
    @EnvironmentObject private var partnerVM: PartnerViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch auth.authState {
            case .unauthenticated:
                NavigationStack {
                    SignInView()
                }
            case .onboarding:
                onboardingFlow
            case .solo:
                SoloDashboardView()
            case .user(let paired):
                UserDashboardView(isPaired: paired)
            case .monitor(let paired):
                MonitorDashboardView(isPaired: paired)
            case .breakGlassActive:
                UserDashboardView(isPaired: true)
            }
        }
        .task {
            await CloudKitSchemaBootstrap.initializeIfNeeded()
            await partnerVM.loadPersistedState()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                ScreenTimeService.shared.refreshAuthorizationStatus()
                Task { await auth.restoreSessionIfPossible() }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: authStateKey)
    }

    /// Stable key for animation across associated-value states.
    private var authStateKey: String {
        switch auth.authState {
        case .unauthenticated: return "unauth"
        case .onboarding: return "onboard-\(String(describing: auth.postAuthStep))"
        case .solo: return "solo"
        case .user(let p): return "user-\(p)"
        case .monitor(let p): return "mon-\(p)"
        case .breakGlassActive(let d): return "bg-\(d.timeIntervalSince1970)"
        }
    }

    @ViewBuilder
    private var onboardingFlow: some View {
        switch auth.postAuthStep {
        case .modeSelection:
            ModeSelectionView()
        case .soloProfile:
            SoloOnboardingView()
        case .userProfile:
            UserOnboardingView()
        case .monitorProfile:
            MonitorOnboardingView()
        case .prdHealth:
            OnboardingHealthView()
        case .prdManual:
            OnboardingManualDataView()
        case .prdCalorie:
            OnboardingCalorieGoalView()
        case .prdApps:
            OnboardingAppBlockingView()
        case .prdPairingPrompt:
            OnboardingPairingPromptView()
        case .prdRoleSelection:
            PartnershipRoleSelectionView()
        case .prdComplete:
            OnboardingCompleteView()
        }
    }
}
