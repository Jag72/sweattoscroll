// Views/Auth/ModeSelectionView.swift
// Post–Sign in with Apple: pick Solo, User (monitored), or Monitor.

import SwiftUI

struct ModeSelectionView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Text("How will you use Sweat2Scroll?")
                        .font(.display(22))
                        .foregroundColor(.ink)
                        .multilineTextAlignment(.center)
                        .padding(.top, 24)

                    Text("You can change pairing later; this only sets your primary path.")
                        .font(.subheadline)
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    modeCard(
                        title: "Just me",
                        subtitle: "Solo mode — no partner. Earn scroll from your own goals.",
                        icon: "figure.run",
                        color: .electricOrange
                    ) { select(.solo) }

                    modeCard(
                        title: "I want to be monitored",
                        subtitle: "Someone you trust sets policy and holds you accountable.",
                        icon: "hand.raised.fill",
                        color: .deepTeal
                    ) { select(.user) }

                    modeCard(
                        title: "I want to monitor someone",
                        subtitle: "Guardian / partner — generate a 6-digit code for them to enter.",
                        icon: "person.2.badge.key.fill",
                        color: Color(hex: "#A855F7")
                    ) { select(.monitor) }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.rose)
                            .padding()
                    }

                    if isSaving {
                        ProgressView()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.light)
    }

    private func modeCard(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color)
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.ink)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundColor(.muted)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func select(_ mode: AppMode) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await auth.completeModeSelection(mode)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isSaving = false }
        }
    }
}

#Preview {
    ModeSelectionView()
}
