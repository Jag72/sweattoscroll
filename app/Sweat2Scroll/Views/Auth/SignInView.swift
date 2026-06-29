// Views/Auth/SignInView.swift
// Returning-user screen, pushed from `SignUpView` (the auth root).
// Username + password sign in, plus Apple / Google one-tap. Tapping
// "Sign Up" pops back to `SignUpView` for first-time accounts.

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var authError: String?
    @State private var showGoogleSoon = false
    @State private var showForgotPassword = false

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
                        Text("Welcome back")
                            .font(.display(26))
                            .foregroundColor(.ink)
                    }
                    Text("Sign in to check your progress and manage your shield.")
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
                            accessibilityFieldID: "signIn.username"
                        )

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
                    .padding(.top, 8)

                    HStack {
                        Spacer()
                        Button("Forgot Password?") { showForgotPassword = true }
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

                    #if DEBUG
                    devCredentialsHint
                    #endif

                    AuthDividerOr()

                    AuthSocialButtons(context: .signIn, showGoogleSoon: $showGoogleSoon) { result in
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
                            dismiss()
                        } label: {
                            Text("Sign Up")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.electricOrange)
                        }
                        .accessibilityIdentifier("signIn.goToSignUp")
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
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            authError = nil
            auth.lastAuthError = nil
        }
    }

    /// True for either the DEBUG dev shortcut or a real, non-empty login.
    private var isSignInReady: Bool {
        #if DEBUG
        if AppSession.isDevCredentialMatch(username: username, password: password) { return true }
        #endif
        return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    @MainActor
    private func signInUsername() async {
        authError = nil
        auth.lastAuthError = nil

        #if DEBUG
        if AppSession.isDevCredentialMatch(username: username, password: password) {
            if UserDefaults.standard.bool(forKey: "onboardingComplete") {
                auth.devSignIn(as: .solo)
            } else {
                auth.devSignIn()
            }
            return
        }
        #endif

        do {
            try await auth.signIn(username: username, password: password)
        } catch {
            // `AuthManager` already surfaces a friendly `lastAuthError` for
            // transient iCloud failures — avoid showing a second, raw error line.
            if auth.lastAuthError == nil {
                authError = error.localizedDescription
            }
        }
    }

    #if DEBUG
    /// Tiny on-screen helper so anyone testing the app knows the simulator login.
    private var devCredentialsHint: some View {
        Button {
            username = AppSession.devUsername
            password = AppSession.devPassword
        } label: {
            // accessibilityIdentifier applied to the outer button below.
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
