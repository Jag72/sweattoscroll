// AppLaunchFlow.swift
// Chains SplashView → TransitionAnimationView → main app (PRD §1).

import SwiftUI

struct AppLaunchFlow<Content: View>: View {
    private enum Phase {
        case splash, transition, main
    }

    @State private var phase = Phase.splash
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            switch phase {
            case .splash:
                SplashView { phase = .transition }
            case .transition:
                TransitionAnimationView { phase = .main }
            case .main:
                content()
            }
        }
    }
}
