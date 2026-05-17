// Views/Auth/SignInView.swift
// First screen the user sees on app launch when they don't have a session.
// Email + password sign in, plus Apple / Google one-tap. Tapping "Sign Up"
// navigates forward to `SignUpView` for first-time accounts.

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var authError: String?
    @State private var showGoogleSoon = false
    @State private var showForgotPassword = false
    @State private var showSignUp = false

    /// Maps `ASAuthorizationError` (e.g. 1000 unknown → missing capability) to actionable copy.
    private static func friendlyAuthError(_ error: Error) -> String {
        if let authErr = error as? ASAuthorizationError {
            switch authErr.code {
            case .canceled:
                return "Sign in was canceled."
            case .failed:
                return "Sign in failed. Try again or check Apple ID settings."
            case .invalidResponse, .notHandled:
                return "Couldn't complete sign in. Try again."
            case .unknown:
                return "Sign in with Apple isn't set up for this build. In Xcode: Target → Signing & Capabilities → add \"Sign In with Apple\", and enable it for this App ID at developer.apple.com."
            @unknown default:
                return authErr.localizedDescription
            }
        }
        return error.localizedDescription
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
                            icon: "envelope.fill",
                            placeholder: "Email",
                            text: $email,
                            keyboardType: .emailAddress,
                            textContentType: .emailAddress,
                            accessibilityFieldID: "signIn.email"
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
                        action: { Task { await signInEmail() } }
                    )

                    #if DEBUG
                    devCredentialsHint
                    #endif

                    dividerOr
                    socialButtons

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
                            showSignUp = true
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
            Text("Google Sign-In will be added with the GoogleSignIn SDK. Use Sign in with Apple or email for now.")
        }
        .alert("Reset password", isPresented: $showForgotPassword) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Email-based password reset isn't wired up yet in this build. If you signed in with Apple, recover from your Apple ID. Otherwise email support@sweat2scroll.app and we'll reset it manually.")
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showSignUp) {
            NavigationStack { SignUpView() }
        }
        .onChange(of: auth.authState) { newState in
            if newState != .unauthenticated { dismiss() }
        }
    }

    private var dividerOr: some View {
        HStack {
            Rectangle().fill(Color.muted.opacity(0.25)).frame(height: 1)
            Text("or").font(.caption).foregroundColor(.muted).padding(.horizontal, 10)
            Rectangle().fill(Color.muted.opacity(0.25)).frame(height: 1)
        }
    }

    private var socialButtons: some View {
        VStack(spacing: 10) {
            Button {
                showGoogleSoon = true
            } label: {
                HStack {
                    Image(systemName: "g.circle.fill")
                    Text("Continue with Google")
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .foregroundColor(.ink)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ringTrack, lineWidth: 1))
            }
            .accessibilityIdentifier("signIn.google")

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { @MainActor in
                    authError = nil
                    switch result {
                    case .success(let authorization):
                        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                            await auth.handleAppleCredential(credential)
                        }
                    case .failure(let error):
                        authError = Self.friendlyAuthError(error)
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            // The underlying `ASAuthorizationAppleIDButton` (UIKit) installs
            // a hard internal `width <= 375` constraint on itself. On iPhone
            // Plus / iPad, the SwiftUI host parent grows past 375 (we saw
            // 382 in production logs) and UIKit logs an "unable to satisfy
            // constraints" warning every time the view appears. We cap the
            // host at 375 to match the button's own limit, then center the
            // resulting block. NB: this WIDTH cap must be set BEFORE the
            // height frame — order matters in SwiftUI's layout pipeline.
            .frame(maxWidth: 375)
            .frame(height: 50)
            .frame(maxWidth: .infinity)  // outer wrapper centers the 375-wide button
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("signIn.apple")
        }
    }

    /// True for either the DEBUG dev shortcut or a real, validly-formatted login.
    private var isSignInReady: Bool {
        #if DEBUG
        if AppSession.isDevCredentialMatch(username: email, password: password) { return true }
        #endif
        return SignUpView.isValidEmail(email) && !password.isEmpty
    }

    @MainActor
    private func signInEmail() async {
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

        do {
            try await auth.signInWithEmail(email: email, password: password)
        } catch {
            authError = error.localizedDescription
        }
    }

    #if DEBUG
    /// Tiny on-screen helper so anyone testing the app knows the simulator login.
    private var devCredentialsHint: some View {
        Button {
            email = AppSession.devUsername
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
