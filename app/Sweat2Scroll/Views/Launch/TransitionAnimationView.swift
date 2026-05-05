// TransitionAnimationView.swift
// Bridges the dark splash to the cream-paper auth/landing screens.
// A circular reveal expands from the brand mark while the logo gently scales up,
// the background morphs from ink → paper, and a subtle orange flare pulses
// before handing off (~1.0s total).

import SwiftUI

struct TransitionAnimationView: View {
    var onFinished: () -> Void

    @State private var revealRadius: CGFloat = 0
    @State private var logoScale: CGFloat = 0.85
    @State private var logoOpacity: Double = 1
    @State private var flareOpacity: Double = 0

    private let duration: Double = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dark background underneath (the splash hand-off).
                Color(hex: "#0B0B0F").ignoresSafeArea()

                // Circular reveal of the cream paper background.
                Circle()
                    .fill(Color.paper)
                    .frame(width: revealRadius * 2, height: revealRadius * 2)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .ignoresSafeArea()

                // Soft orange flare burst at the centre.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.electricOrange.opacity(0.55),
                                Color.electricOrange.opacity(0),
                            ],
                            center: .center,
                            startRadius: 5,
                            endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .opacity(flareOpacity)
                    .blur(radius: 40)
                    .blendMode(.screen)

                Sweat2ScrollLogo(size: 124)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
            }
            .ignoresSafeArea()
            .onAppear {
                animate(in: geo.size)
            }
        }
    }

    private func animate(in size: CGSize) {
        let maxRadius = sqrt(size.width * size.width + size.height * size.height) / 2 + 40

        withAnimation(.easeOut(duration: duration * 0.85)) {
            revealRadius = maxRadius
        }
        withAnimation(.easeIn(duration: 0.35).delay(0.2)) {
            flareOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.45)) {
            flareOpacity = 0
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            logoScale = 1.05
        }
        withAnimation(.easeIn(duration: 0.3).delay(duration - 0.15)) {
            logoOpacity = 0
            logoScale = 0.92
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) {
            onFinished()
        }
    }
}

#Preview {
    TransitionAnimationView {}
}
