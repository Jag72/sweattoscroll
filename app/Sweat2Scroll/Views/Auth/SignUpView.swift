// SignUpView.swift
// The Create Account screen, pushed from SignInView. Clean, Cinemark-inspired:
// optional name, email, password + confirm password with inline validation,
// plus Google / Apple one-tap. "Sign In" pops back to the sign-in screen.

import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss

    var prefillEmail: String = ""

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var authError: String?
    @State private var showForgotPassword = false

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Spacer().frame(height: 28)

                    Sweat2ScrollLogo(size: 68, animated: true)
                    VStack(spacing: 6) {
                        Sweat2ScrollWordmark(size: 20)
                        Text("Create your account")
                            .font(.display(24))
                            .foregroundColor(.ink)
                    }
                    Text("Your health data never leaves this device.")
                        .font(.system(size: 13))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 4)

                    VStack(spacing: 14) {
                        AuthFormField(
                            icon: "person.fill",
                            placeholder: "Full name (optional)",
                            text: $fullName,
                            autocapitalization: .words,
                            disableAutocorrection: false,
                            accessibilityFieldID: "signUp.fullName"
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            AuthFormField(
                                icon: "person.fill",
                                placeholder: "Username or Email",
                                text: $email,
                                textContentType: .username,
                                accessibilityFieldID: "signUp.email"
                            )
                            if showIdentifierError {
                                AuthFieldError("Use a valid email, or a username of 3+ characters.")
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            AuthFormField(
                                icon: "lock.fill",
                                placeholder: "Password",
                                text: $password,
                                textContentType: .newPassword,
                                isSecure: true,
                                showSecure: $showPassword,
                                accessibilityFieldID: "signUp.password"
                            )
                            if showPasswordError {
                                AuthFieldError("Use at least 6 characters.")
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            AuthFormField(
                                icon: "lock.rotation",
                                placeholder: "Confirm password",
                                text: $confirmPassword,
                                textContentType: .newPassword,
                                isSecure: true,
                                showSecure: $showConfirmPassword,
                                accessibilityFieldID: "signUp.confirmPassword"
                            )
                            if showConfirmError {
                                AuthFieldError("Passwords don't match.")
                            }
                        }
                    }

                    PrimaryCTAButton(
                        title: "Create Account",
                        isEnabled: isFormValid,
                        isLoading: auth.isLoadingAuth,
                        accessibilityIdentifier: "signUp.submit",
                        action: { Task { await signUpEmail() } }
                    )

                    AuthDividerOr()

                    AuthSocialButtons(
                        context: .signUp,
                        showGoogleSoon: .constant(false),
                        onGoogle: { Task { await signUpWithGoogle() } }
                    ) { result in
                        Task { @MainActor in
                            authError = nil
                            switch result {
                            case .success(let authorization):
                                if let cred = authorization.credential as? ASAuthorizationAppleIDCredential {
                                    await auth.handleAppleCredential(cred)
                                }
                            case .failure(let error):
                                authError = AuthUX.friendlyAuthError(error)
                            }
                        }
                    }

                    if let err = authError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.rose)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("signUp.localError")
                    }
                    if let err = auth.lastAuthError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.rose)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("signUp.authError")
                    }

                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .font(.subheadline)
                            .foregroundColor(.muted)
                        Button {
                            dismiss()
                        } label: {
                            Text("Sign In")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.electricOrange)
                        }
                        .accessibilityIdentifier("signUp.goToSignIn")
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(username: email) { resetUsername in
                email = resetUsername
                password = ""
                confirmPassword = ""
                authError = nil
                auth.lastAuthError = nil
                dismiss()
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            if email.isEmpty { email = prefillEmail }
            authError = nil
            auth.lastAuthError = nil
        }
    }

    // MARK: - Validation

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showIdentifierError: Bool {
        !trimmedEmail.isEmpty && !Self.isValidIdentifier(trimmedEmail)
    }

    private var showPasswordError: Bool {
        !password.isEmpty && password.count < 6
    }

    private var showConfirmError: Bool {
        !confirmPassword.isEmpty && confirmPassword != password
    }

    private var isFormValid: Bool {
        Self.isValidIdentifier(trimmedEmail) &&
        password.count >= 6 &&
        confirmPassword == password
    }

    /// Account creation accepts either an email (must be well-formed so it can
    /// also populate the CloudKit `email` field) or a plain username (3+ chars).
    static func isValidIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") { return isValidEmail(trimmed) }
        return trimmed.count >= 3
    }

    // MARK: - Actions

    @MainActor
    private func signUpEmail() async {
        authError = nil
        auth.lastAuthError = nil
        guard isFormValid else { return }

        if EmailCredentialStore.hasAccount(email: trimmedEmail) {
            authError = "An account with that username/email already exists. Try signing in instead."
            return
        }

        do {
            try await auth.signUp(
                username: trimmedEmail,
                password: password,
                displayName: fullName
            )
        } catch {
            // `AuthManager` already surfaces a friendly `lastAuthError` for
            // transient iCloud failures — avoid showing a second, raw error line.
            if auth.lastAuthError == nil {
                authError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func signUpWithGoogle() async {
        authError = nil
        auth.lastAuthError = nil
        do {
            let profile = try await GoogleAuthService.shared.signIn()
            await auth.handleGoogleSignIn(
                userID: profile.userID,
                email: profile.email,
                fullName: profile.fullName
            )
        } catch {
            if auth.lastAuthError == nil {
                authError = error.localizedDescription
            }
        }
    }

    /// App-wide email validator: also decides whether an email lands in the
    /// CloudKit `email` slot (see `AuthManager`).
    static func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5, trimmed.contains("@"), trimmed.contains(".") else { return false }
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

#Preview {
    NavigationStack {
        SignUpView()
    }
}
