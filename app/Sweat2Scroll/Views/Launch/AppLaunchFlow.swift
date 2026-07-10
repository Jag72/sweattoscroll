// AppLaunchFlow.swift
// Shows SplashView, then crossfades straight into the main app.

import SwiftUI

struct AppLaunchFlow<Content: View>: View {
    private enum Phase {
        case splash, main
    }

    @State private var phase = Phase.splash
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            switch phase {
            case .splash:
                SplashView { phase = .main }
                    .transition(.opacity)
            case .main:
                content()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }
}
