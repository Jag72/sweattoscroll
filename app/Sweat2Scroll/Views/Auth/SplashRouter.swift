// SplashRouter.swift
// Auth check after splash + transition: signed-in users go straight to their
// dashboard via `RootView`; everyone else lands on Sign Up (returning users
// tap "Sign In" from there). Crossfades between the two states.

import SwiftUI

struct SplashRouter: View {
    @ObservedObject private var auth = AuthManager.shared

    private var isSignedOut: Bool {
        auth.authState == .unauthenticated && !AppSession.hasSessionToken
    }

    var body: some View {
        ZStack {
            if isSignedOut {
                NavigationStack {
                    SignUpView()
                }
                .transition(.opacity)
            } else {
                RootView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isSignedOut)
    }
}
