// SplashView.swift
// First paint after icon launch. Sets the brand tone: deep ink gradient,
// breathing aura around the logo, animated wordmark, and a smooth gradient
// progress bar that finishes in ~2s before handing off to the transition.

import SwiftUI

struct SplashView: View {
    var onFinished: () -> Void

    @State private var logoScale: CGFloat = 0.7
    @State private var logoOpacity: Double = 0
    @State private var auraScale: CGFloat = 0.85
    @State private var auraOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 14
    @State private var taglineOpacity: Double = 0
    @State private var barFraction: CGFloat = 0

    private let totalDuration: Double = 2.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background

                particleField
                    .opacity(0.6)
                    .allowsHitTesting(false)

                VStack(spacing: 28) {
                    Spacer()

                    ZStack {
                        // Breathing aura behind logo
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.electricOrange.opacity(0.45),
                                        Color.electricOrange.opacity(0.0),
                                    ],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 180
                                )
                            )
                            .frame(width: 260, height: 260)
                            .scaleEffect(auraScale)
                            .opacity(auraOpacity)
                            .blur(radius: 18)

                        Sweat2ScrollLogo(size: 124, animated: true)
                            .scaleEffect(logoScale)
                            .opacity(logoOpacity)
                    }

                    VStack(spacing: 10) {
                        Sweat2ScrollWordmark(size: 22, dark: true)
                            .opacity(wordmarkOpacity)
                            .offset(y: wordmarkOffset)
                        Text("Earn your scroll time.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .tracking(2)
                            .foregroundColor(Color.white.opacity(0.55))
                            .textCase(.uppercase)
                            .opacity(taglineOpacity)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                // Progress bar
                VStack {
                    Spacer()
                    progressBar(width: geo.size.width)
                        .padding(.bottom, 64)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear { animate() }
    }

    // MARK: - Background
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#0B0B0F"),
                    Color(hex: "#161617"),
                    Color(hex: "#0B0B0F"),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle vignette warmth from the brand color
            RadialGradient(
                colors: [
                    Color.electricOrange.opacity(0.12),
                    Color.clear,
                ],
                center: .top,
                startRadius: 60,
                endRadius: 380
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Particles
    private var particleField: some View {
        Canvas { context, size in
            let dotCount = 28
            for i in 0..<dotCount {
                let xs = sin(Double(i) * 1.7) * 0.5 + 0.5
                let ys = cos(Double(i) * 2.3) * 0.5 + 0.5
                let x = xs * size.width
                let y = ys * size.height
                let r = CGFloat(1 + (Double(i % 3) * 0.6))
                let alpha = 0.08 + Double(i % 5) * 0.03
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .color(Color.white.opacity(alpha))
                )
            }
        }
    }

    // MARK: - Progress bar
    private func progressBar(width: CGFloat) -> some View {
        let inset: CGFloat = 56
        let barWidth = max(80, width - inset * 2)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: barWidth, height: 4)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#FF8A3D"), Color(hex: "#FF4D1A"), Color(hex: "#FFB347")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(2, barWidth * barFraction), height: 4)
                .shadow(color: Color.electricOrange.opacity(0.6), radius: 8, y: 0)
        }
    }

    // MARK: - Animation
    private func animate() {
        withAnimation(.easeOut(duration: 0.55)) {
            logoOpacity = 1
            logoScale = 1
        }
        withAnimation(.easeOut(duration: 0.9).delay(0.1)) {
            auraOpacity = 1
            auraScale = 1
        }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            auraScale = 1.08
        }
        withAnimation(.easeOut(duration: 0.7).delay(0.45)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }
        withAnimation(.easeOut(duration: 0.7).delay(0.7)) {
            taglineOpacity = 1
        }
        withAnimation(.easeInOut(duration: totalDuration - 0.1).delay(0.1)) {
            barFraction = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.05) {
            onFinished()
        }
    }
}

#Preview {
    SplashView {}
}
