// SplashRouter.swift
// Auth check after splash + transition: signed-in users go straight to their
// dashboard via `RootView`; everyone else lands on Sign Up (returning users
// tap "Sign In" from there). Crossfades between the two states.
//
// Cold-launch biometric gate: when a saved session exists and Face ID /
// Touch ID is enabled, the dashboard is locked behind `BiometricLockView`
// once per process launch. Backgrounding and returning does NOT re-lock —
// only a fresh launch (including after iOS terminated the app) does.

import SwiftUI

struct SplashRouter: View {
    @ObservedObject private var auth = AuthManager.shared

    /// Unlocked once per process launch. Starts locked only when there is a
    /// session worth protecting AND the device can authenticate.
    @State private var biometricUnlocked = !BiometricAuthService.shared.shouldGateOnLaunch
        || !AppSession.hasSessionToken

    private var isSignedOut: Bool {
        auth.authState == .unauthenticated && !AppSession.hasSessionToken
    }

    var body: some View {
        ZStack {
            if isSignedOut {
                NavigationStack {
                    SignInView()
                }
                .transition(.opacity)
            } else if !biometricUnlocked {
                BiometricLockView {
                    withAnimation { biometricUnlocked = true }
                }
                .transition(.opacity)
            } else {
                RootView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isSignedOut)
        .animation(.easeInOut(duration: 0.35), value: biometricUnlocked)
    }
}
