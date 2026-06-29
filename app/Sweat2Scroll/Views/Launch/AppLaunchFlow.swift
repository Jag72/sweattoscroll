// AppLaunchFlow.swift
// Chains SplashView → TransitionAnimationView → main app (PRD §1),
// crossfading between phases so there are no hard cuts.

import SwiftUI

struct AppLaunchFlow<Content: View>: View {
    private enum Phase {
        case splash, transition, main
    }

    @State private var phase = Phase.splash
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView { phase = .transition }
                    .transition(.opacity)
            case .transition:
                TransitionAnimationView { phase = .main }
                    .transition(.opacity)
            case .main:
                content()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }
}
