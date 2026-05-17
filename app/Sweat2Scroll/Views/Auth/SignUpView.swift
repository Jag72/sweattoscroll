// SignUpView.swift
// Sign-up form: First name + Last name + email + optional phone + password.
// Apple sign-up still creates the account in one tap; Google is a placeholder
// until the GoogleSignIn SDK is wired in.

import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var authError: String?
    @State private var showGoogleSoon = false

    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Self.isValidEmail(email) &&
        password.count >= 6 &&
        password == confirmPassword
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
                    Spacer().frame(height: 12)

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
                    Text("A few details so we can save your goals and pair you with your accountability partner.")
                        .font(.system(size: 14))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    formFields

                    PrimaryCTAButton(
                        title: "Create account",
                        isEnabled: isFormValid,
                        isLoading: auth.isLoadingAuth,
                        accessibilityIdentifier: "signUp.submit",
                        action: { Task { await signUpEmail() } }
                    )

                    dividerOr
                    socialButtons

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
                        .accessibilityIdentifier("signUp.backToSignIn")
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
        .preferredColorScheme(.light)
        .onChange(of: auth.authState) { newState in
            if newState != .unauthenticated { dismiss() }
        }
    }

    // MARK: - Form

    private var formFields: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                AuthFormField(
                    icon: "person.fill",
                    placeholder: "First name",
                    text: $firstName,
                    textContentType: .givenName,
                    autocapitalization: .words,
                    disableAutocorrection: true,
                    accessibilityFieldID: "signUp.firstName"
                )
                AuthFormField(
                    icon: "person",
                    placeholder: "Last name",
                    text: $lastName,
                    textContentType: .familyName,
                    autocapitalization: .words,
                    disableAutocorrection: true,
                    accessibilityFieldID: "signUp.lastName"
                )
            }

            AuthFormField(
                icon: "envelope.fill",
                placeholder: "Email",
                text: $email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                accessibilityFieldID: "signUp.email"
            )

            AuthFormField(
                icon: "phone.fill",
                placeholder: "Phone (optional)",
                text: $phone,
                keyboardType: .phonePad,
                textContentType: .telephoneNumber,
                accessibilityFieldID: "signUp.phone"
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

            AuthFormField(
                icon: "lock.shield",
                placeholder: "Confirm password",
                text: $confirmPassword,
                textContentType: .newPassword,
                isSecure: true,
                showSecure: $showConfirmPassword,
                accessibilityFieldID: "signUp.confirmPassword"
            )

            if !confirmPassword.isEmpty && password != confirmPassword {
                Label("Passwords don't match", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.rose)
                    .accessibilityIdentifier("signUp.passwordMismatch")
            }
        }
        .padding(.top, 4)
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
            .accessibilityIdentifier("signUp.google")

            SignInWithAppleButton(.signUp) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { @MainActor in
                    authError = nil
                    switch result {
                    case .success(let authorization):
                        if let cred = authorization.credential as? ASAuthorizationAppleIDCredential {
                            await auth.handleAppleCredential(cred)
                        }
                    case .failure(let error):
                        authError = error.localizedDescription
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            // See SignInView for the constraint-conflict explanation. Cap
            // the host at the button's internal 375pt limit, then center.
            .frame(maxWidth: 375)
            .frame(height: 50)
            .frame(maxWidth: .infinity)  // outer wrapper centers the 375-wide button
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("signUp.apple")
        }
    }

    // MARK: - Actions

    @MainActor
    private func signUpEmail() async {
        authError = nil
        guard isFormValid else { return }
        do {
            try await auth.signUpWithEmail(
                firstName: firstName,
                lastName: lastName,
                email: email,
                phone: phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phone,
                password: password
            )
        } catch {
            authError = error.localizedDescription
        }
    }

    static func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5, trimmed.contains("@"), trimmed.contains(".") else { return false }
        let pattern = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Primary CTA helper used by auth screens
struct PrimaryCTAButton: View {
    let title: String
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading { ProgressView().tint(.white) }
                Text(title).fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isEnabled
                    ? LinearGradient(colors: [.electricOrange, Color(hex: "#FF9A62")],
                                     startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color.muted.opacity(0.25), Color.muted.opacity(0.2)],
                                     startPoint: .leading, endPoint: .trailing)
            )
            .foregroundColor(isEnabled ? .white : .muted)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: isEnabled ? Color.electricOrange.opacity(0.25) : .clear, radius: 12, y: 4)
        }
        .disabled(!isEnabled || isLoading)
        .modifier(PrimaryCTAButtonAccessibilityID(id: accessibilityIdentifier))
    }
}

private struct PrimaryCTAButtonAccessibilityID: ViewModifier {
    let id: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}
