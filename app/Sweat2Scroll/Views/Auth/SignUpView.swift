// SignUpView.swift
// Root auth screen for users without a session (auth check routes here).
// Minimal account creation: username + password, plus Google / Apple one-tap.
// "Sign In" pushes `SignInView` for returning accounts.

import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @ObservedObject private var auth = AuthManager.shared

    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var authError: String?
    @State private var showGoogleSoon = false
    @State private var showForgotPassword = false
    @State private var showSignIn = false

    private var isFormValid: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
        password.count >= 6
    }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            Circle()
                .fill(Color.electricOrange.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: 130, y: -240)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    Spacer().frame(height: 28)

                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.electricOrange.opacity(0.18),
                                        Color.clear,
                                    ],
                                    center: .center,
                                    startRadius: 2,
                                    endRadius: 110
                                )
                            )
                            .frame(width: 180, height: 180)
                            .blur(radius: 10)
                        Sweat2ScrollLogo(size: 84, animated: true)
                    }
                    VStack(spacing: 8) {
                        Sweat2ScrollWordmark(size: 22)
                        Text("Create your account")
                            .font(.display(26))
                            .foregroundColor(.ink)
                    }
                    Text("Pick a username and you're in. Your health data never leaves this device.")
                        .font(.system(size: 14))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    VStack(spacing: 14) {
                        AuthFormField(
                            icon: "person.fill",
                            placeholder: "Username",
                            text: $username,
                            textContentType: .username,
                            accessibilityFieldID: "signUp.username"
                        )

                        AuthFormField(
                            icon: "lock.fill",
                            placeholder: "Password (min 6 chars)",
                            text: $password,
                            textContentType: .newPassword,
                            isSecure: true,
                            showSecure: $showPassword,
                            accessibilityFieldID: "signUp.password"
                        )
                    }
                    .padding(.top, 8)

                    HStack {
                        Spacer()
                        Button("Forgot Password?") { showForgotPassword = true }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.muted)
                            .accessibilityIdentifier("signUp.forgotPassword")
                    }

                    PrimaryCTAButton(
                        title: "Create Account",
                        isEnabled: isFormValid,
                        isLoading: auth.isLoadingAuth,
                        accessibilityIdentifier: "signUp.submit",
                        action: { Task { await signUpUsername() } }
                    )

                    AuthDividerOr()

                    AuthSocialButtons(context: .signUp, showGoogleSoon: $showGoogleSoon) { result in
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
                            showSignIn = true
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
        .alert("Google Sign-In", isPresented: $showGoogleSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Google Sign-In will be added with the GoogleSignIn SDK. Use Sign in with Apple or username for now.")
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(username: username) { resetUsername in
                username = resetUsername
                password = ""
                authError = nil
                auth.lastAuthError = nil
                showSignIn = true
            }
        }
        .navigationDestination(isPresented: $showSignIn) {
            SignInView()
        }
        .preferredColorScheme(.light)
        .onAppear {
            authError = nil
            auth.lastAuthError = nil
        }
    }

    // MARK: - Actions

    @MainActor
    private func signUpUsername() async {
        authError = nil
        guard isFormValid else { return }
        do {
            try await auth.signUp(username: username, password: password)
        } catch {
            // `AuthManager` already surfaces a friendly `lastAuthError` for
            // transient iCloud failures — avoid showing a second, raw error line.
            if auth.lastAuthError == nil {
                authError = error.localizedDescription
            }
        }
    }

    /// Kept as the app-wide email validator: decides whether an email-shaped
    /// username also lands in the CloudKit `email` slot (see `AuthManager`).
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
