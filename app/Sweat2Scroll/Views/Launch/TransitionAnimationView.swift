// TransitionAnimationView.swift
// Bridges the dark splash to the auth screens: a clean white canvas where the
// brand-orange runner sprints left → right along a thin track, painting an
// orange trail behind it (echoing the splash progress bar), with motion
// ghosts and a gentle bob. Fades out and hands off after ~1.7s.

import SwiftUI

struct TransitionAnimationView: View {
    var onFinished: () -> Void

    @State private var startDate: Date?
    @State private var contentOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0

    /// Time the runner spends crossing the screen.
    private let runDuration: Double = 1.3
    /// Full lifetime of the screen including fade in/out.
    private let totalDuration: Double = 1.7

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()

                TimelineView(.animation) { timeline in
                    let elapsed = startDate.map { timeline.date.timeIntervalSince($0) } ?? 0
                    runnerScene(elapsed: elapsed, size: geo.size)
                }
                .opacity(contentOpacity)

                VStack {
                    Spacer()
                    Sweat2ScrollWordmark(size: 18)
                        .opacity(wordmarkOpacity)
                        .padding(.bottom, 72)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .onAppear { animate() }
    }

    // MARK: - Runner scene

    @ViewBuilder
    private func runnerScene(elapsed: TimeInterval, size: CGSize) -> some View {
        let t = min(max(elapsed / runDuration, 0), 1)
        let eased = smoothstep(t)
        let trackY = size.height * 0.46
        // Start fully off-screen left, finish off-screen right.
        let startX: CGFloat = -70
        let endX = size.width + 70
        let x = startX + (endX - startX) * eased
        // Bob + lean only while actually moving.
        let moving = t > 0 && t < 1
        let bob = moving ? sin(elapsed * 16) * 4 : 0
        let lean: Double = moving ? 7 : 0

        ZStack {
            // Track line the runner travels along.
            Capsule()
                .fill(Color.ringTrack.opacity(0.7))
                .frame(width: size.width - 96, height: 3)
                .position(x: size.width / 2, y: trackY + 34)

            // Orange trail filling in behind the runner.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#FF8A3D"), Color.electricOrange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(2, min(x - 48, size.width - 96)), height: 3)
                .position(x: 48 + max(2, min(x - 48, size.width - 96)) / 2, y: trackY + 34)
                .shadow(color: Color.electricOrange.opacity(0.45), radius: 6)

            // Motion ghosts trailing the runner.
            ForEach(1..<3) { i in
                let ghostEased = smoothstep(max(t - Double(i) * 0.045, 0))
                let ghostX = startX + (endX - startX) * ghostEased
                Image(systemName: "figure.run")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundColor(Color.electricOrange.opacity(i == 1 ? 0.22 : 0.10))
                    .position(x: ghostX, y: trackY + bob)
            }

            // The runner.
            Image(systemName: "figure.run")
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(.electricOrange)
                .rotationEffect(.degrees(lean))
                .position(x: x, y: trackY + bob)
                .shadow(color: Color.electricOrange.opacity(0.35), radius: 10, y: 4)
        }
    }

    /// Ease-in-out (smoothstep) — soft launch, sprint, soft arrival.
    private func smoothstep(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    // MARK: - Lifecycle

    private func animate() {
        startDate = Date()
        withAnimation(.easeOut(duration: 0.25)) {
            contentOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            wordmarkOpacity = 1
        }
        withAnimation(.easeIn(duration: 0.3).delay(totalDuration - 0.35)) {
            contentOpacity = 0
            wordmarkOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            onFinished()
        }
    }
}

#Preview {
    TransitionAnimationView {}
}
