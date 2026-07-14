// Views/Auth/SignInView.swift
// The sign-in screen for Sweat2Scroll (clean, Cinemark-inspired).
// Email + password for returning accounts, plus Sign in with Apple and
// Continue with Google. New users tap "Create Account" for the sign-up page.

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @ObservedObject private var auth = AuthManager.shared

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var authError: String?
    @State private var showForgotPassword = false
    @State private var showCreateAccount = false

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Spacer().frame(height: 44)

                    Sweat2ScrollLogo(size: 76, animated: true)
                    Sweat2ScrollWordmark(size: 22)
                        .padding(.bottom, 10)

                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            AuthFormField(
                                icon: "person.fill",
                                placeholder: "Username or Email",
                                text: $email,
                                textContentType: .username,
                                accessibilityFieldID: "signIn.username"
                            )
                            if showIdentifierError {
                                AuthFieldError("Enter your username or email.")
                            }
                        }

                        AuthFormField(
                            icon: "lock.fill",
                            placeholder: "Password",
                            text: $password,
                            textContentType: .password,
                            isSecure: true,
                            showSecure: $showPassword,
                            accessibilityFieldID: "signIn.password"
                        )
                    }

                    HStack {
                        Spacer()
                        Button("Forgot your Password?") { showForgotPassword = true }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.muted)
                            .accessibilityIdentifier("signIn.forgotPassword")
                    }

                    PrimaryCTAButton(
                        title: "Sign In",
                        isEnabled: isSignInReady,
                        isLoading: auth.isLoadingAuth,
                        accessibilityIdentifier: "signIn.submit",
                        action: { Task { await signInUsername() } }
                    )

                    AuthDividerOr()

                    AuthSocialButtons(
                        context: .signIn,
                        showGoogleSoon: .constant(false),
                        onGoogle: { Task { await signInWithGoogle() } }
                    ) { result in
                        Task { @MainActor in
                            authError = nil
                            switch result {
                            case .success(let authorization):
                                if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                    await auth.handleAppleCredential(credential)
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
                            .accessibilityIdentifier("signIn.localError")
                    }
                    if let err = auth.lastAuthError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.rose)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("signIn.authError")
                    }

                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .font(.subheadline)
                            .foregroundColor(.muted)
                        Button {
                            showCreateAccount = true
                        } label: {
                            Text("Create Account")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.electricOrange)
                        }
                        .accessibilityIdentifier("signIn.goToCreateAccount")
                    }
                    .padding(.top, 4)

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(username: email) { resetUsername in
                email = resetUsername
                password = ""
                authError = nil
                auth.lastAuthError = nil
            }
        }
        .navigationDestination(isPresented: $showCreateAccount) {
            SignUpView(prefillEmail: email)
        }
        .preferredColorScheme(.light)
        .onAppear {
            authError = nil
            auth.lastAuthError = nil
        }
    }

    // MARK: - Validation

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Login accepts either a username or an email, so we only require a
    /// minimally sensible identifier here (real verification happens against
    /// the local credential store on submit).
    private var showIdentifierError: Bool {
        !trimmedEmail.isEmpty && trimmedEmail.count < 3
    }

    /// True for either the DEBUG dev shortcut or a username/email + password.
    private var isSignInReady: Bool {
        #if DEBUG
        if AppSession.isDevCredentialMatch(username: email, password: password) { return true }
        #endif
        return trimmedEmail.count >= 3 && !password.isEmpty
    }

    @MainActor
    private func signInUsername() async {
        authError = nil
        auth.lastAuthError = nil

        #if DEBUG
        if AppSession.isDevCredentialMatch(username: email, password: password) {
            if UserDefaults.standard.bool(forKey: "onboardingComplete") {
                auth.devSignIn(as: .solo)
            } else {
                auth.devSignIn()
            }
            return
        }
        #endif

        guard trimmedEmail.count >= 3 else {
            authError = "Enter your username or email."
            return
        }
        guard !password.isEmpty else {
            authError = "Enter your password."
            return
        }

        // Sign-in only verifies existing accounts (username OR email). New users
        // go through the dedicated Create Account page so onboarding is explicit.
        guard EmailCredentialStore.hasAccount(email: trimmedEmail) else {
            authError = "No account found. Check your username/email, or tap Create Account. For Apple/Google accounts, use the buttons below."
            return
        }

        do {
            try await auth.signIn(username: trimmedEmail, password: password)
        } catch {
            // `AuthManager` already surfaces a friendly `lastAuthError` for
            // transient iCloud failures — avoid showing a second, raw error line.
            if auth.lastAuthError == nil {
                authError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func signInWithGoogle() async {
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

    #if DEBUG
    /// Tiny on-screen helper so anyone testing the app knows the simulator login.
    private var devCredentialsHint: some View {
        Button {
            email = AppSession.devUsername
            password = AppSession.devPassword
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 11))
                Text("Tester login: ")
                    .font(.system(size: 11))
                + Text("\(AppSession.devUsername) / \(AppSession.devPassword)")
                    .font(.system(size: 11, weight: .semibold))
                Text("· Tap to fill")
                    .font(.system(size: 11))
            }
            .foregroundColor(.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.ink.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.ringTrack, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("signIn.devChip")
    }
    #endif
}

#Preview {
    NavigationStack {
        SignInView()
    }
}
