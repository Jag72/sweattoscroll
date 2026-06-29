// Views/Auth/ForgotPasswordView.swift
// Device-local password reset for username/password accounts.
//
// There is no auth backend (see EmailCredentialStore): passwords live only in
// this device's Keychain. The username→ID hash is deterministic, so resetting
// the password here keeps the same account/CloudKit profile linked. Users who
// signed up with Apple should recover via their Apple ID instead.

import SwiftUI

struct ForgotPasswordView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss

    /// Prefilled from the sign-in form when available.
    @State var username: String

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showNew = false
    @State private var showConfirm = false
    @State private var errorMessage: String?
    @State private var didReset = false

    /// Called with the (trimmed) username after a successful reset so the
    /// caller can prefill the sign-in field.
    var onReset: ((String) -> Void)?

    init(username: String = "", onReset: ((String) -> Void)? = nil) {
        _username = State(initialValue: username)
        self.onReset = onReset
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var passwordsMatch: Bool {
        !confirmPassword.isEmpty && newPassword == confirmPassword
    }

    private var isValid: Bool {
        !trimmedUsername.isEmpty &&
        newPassword.count >= 6 &&
        newPassword == confirmPassword
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paper.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        Spacer().frame(height: 8)

                        Sweat2ScrollLogo(size: 64, animated: false)

                        VStack(spacing: 8) {
                            Text(didReset ? "Password reset" : "Reset password")
                                .font(.display(24))
                                .foregroundColor(.ink)
                            Text(headerSubtitle)
                                .font(.system(size: 14))
                                .foregroundColor(.muted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }

                        if didReset {
                            successContent
                        } else {
                            formContent
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("forgotPassword.close")
                }
            }
            .preferredColorScheme(.light)
        }
    }

    private var headerSubtitle: String {
        didReset
            ? "Your password was updated on this device. Sign in with your new password."
            : "Set a new password for your account on this device."
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                AuthFormField(
                    icon: "person.fill",
                    placeholder: "Username",
                    text: $username,
                    textContentType: .username,
                    accessibilityFieldID: "forgotPassword.username"
                )

                AuthFormField(
                    icon: "lock.fill",
                    placeholder: "New password (min 6 chars)",
                    text: $newPassword,
                    textContentType: .newPassword,
                    isSecure: true,
                    showSecure: $showNew,
                    accessibilityFieldID: "forgotPassword.newPassword"
                )

                AuthFormField(
                    icon: "lock.shield",
                    placeholder: "Confirm new password",
                    text: $confirmPassword,
                    textContentType: .newPassword,
                    isSecure: true,
                    showSecure: $showConfirm,
                    accessibilityFieldID: "forgotPassword.confirmPassword"
                )
            }

            if !confirmPassword.isEmpty && !passwordsMatch {
                Label("Passwords don't match", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.rose)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryCTAButton(
                title: "Reset password",
                isEnabled: isValid,
                accessibilityIdentifier: "forgotPassword.submit",
                action: resetPassword
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.rose)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("forgotPassword.error")
            }

            appleRecoveryNote
        }
    }

    private var appleRecoveryNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(.muted)
            Text("Passwords are stored only on this device for privacy. If you signed up with Apple, use Sign in with Apple to recover instead.")
                .font(.caption)
                .foregroundColor(.muted)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.ink.opacity(0.04))
        )
        .padding(.top, 4)
    }

    // MARK: - Success

    private var successContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(.electricOrange)
                .padding(.top, 8)

            PrimaryCTAButton(
                title: "Back to sign in",
                accessibilityIdentifier: "forgotPassword.done",
                action: {
                    onReset?(trimmedUsername)
                    dismiss()
                }
            )
        }
    }

    // MARK: - Actions

    private func resetPassword() {
        errorMessage = nil
        guard isValid else { return }
        do {
            try auth.resetLocalPassword(username: trimmedUsername, newPassword: newPassword)
            newPassword = ""
            confirmPassword = ""
            didReset = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ForgotPasswordView(username: "athlete@example.com")
}
