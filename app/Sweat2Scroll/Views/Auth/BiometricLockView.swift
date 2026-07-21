// Views/Auth/BiometricLockView.swift
// Cold-launch lock screen shown when a saved session exists and Face ID /
// Touch ID is enabled. Auto-prompts on appear; offers retry and a
// password-fallback that signs out to the normal login page.

import SwiftUI

struct BiometricLockView: View {
    /// Called when biometric auth succeeds — parent reveals the app.
    let onUnlocked: () -> Void

    @State private var isAuthenticating = false
    @State private var failedOnce = false

    private var biometry: BiometricAuthService.BiometryKind {
        BiometricAuthService.shared.availableBiometry
    }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.electricOrange.opacity(0.12))
                        .frame(width: 108, height: 108)
                    Image(systemName: biometry.systemImage)
                        .font(.system(size: 46, weight: .medium))
                        .foregroundColor(.electricOrange)
                }

                VStack(spacing: 6) {
                    Text("Welcome back")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.ink)
                    Text("Unlock with \(biometry.label) to pick up where you left off.")
                        .font(.system(size: 14))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                if failedOnce {
                    Button(action: attemptUnlock) {
                        HStack(spacing: 8) {
                            if isAuthenticating {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: biometry.systemImage)
                            }
                            Text("Try \(biometry.label) Again")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.electricOrange)
                        )
                    }
                    .disabled(isAuthenticating)
                    .padding(.horizontal, 32)
                }

                Spacer()

                Button("Sign in with password instead") {
                    AuthManager.shared.signOut()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)
                .padding(.bottom, 32)
            }
        }
        .onAppear(perform: attemptUnlock)
    }

    private func attemptUnlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            let ok = await BiometricAuthService.shared.authenticate()
            isAuthenticating = false
            if ok {
                onUnlocked()
            } else {
                failedOnce = true
            }
        }
    }
}

#Preview { BiometricLockView(onUnlocked: {}) }
