// SplashRouter.swift
// After splash + transition, send users without a session straight to Sign In;
// otherwise hand off to `RootView`. New users tap "Sign Up" from there.

import SwiftUI

struct SplashRouter: View {
    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        Group {
            if auth.authState == .unauthenticated && !AppSession.hasSessionToken {
                NavigationStack {
                    SignInView()
                }
            } else {
                RootView()
            }
        }
    }
}
