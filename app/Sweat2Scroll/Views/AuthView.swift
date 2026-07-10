// Views/AuthView.swift
// Auth screen with three modes: Login, User Sign-Up, Partner Join.
// FinalTheme: auth uses the deep-teal accent end-to-end (entry experience);
// orange is reserved for in-app energy. After success → DashboardView via UserDefaults flag.

import SwiftUI
import AuthenticationServices

// MARK: - Auth Mode
enum AuthMode {
    case login
    case signup
    case partnerJoin
}

// MARK: - Auth View
struct AuthView: View {
    @EnvironmentObject var onboardingVM: OnboardingViewModel
    @Environment(\.dismiss) var dismiss

    let initialMode: AuthMode

    @State private var mode: AuthMode
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var partnerCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var agreedToTerms = false
    @State private var appeared = false

    init(initialMode: AuthMode) {
        self.initialMode = initialMode
        _mode = State(initialValue: initialMode)
    }

    // MARK: - Accent (FinalTheme: teal for the whole auth flow)
    private var accent: Color { .deepTeal }

    private var accentGradient: [Color] {
        [Color.deepTeal, Color(hex: "#1A7A90")]
    }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            // Ambient blob
            Circle()
                .fill(accent.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: 130, y: -220)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Back button
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(.subheadline)
                        }
                        .foregroundColor(.muted)
                    }
                    .padding(.leading, 22)
                    .padding(.top, 18)
                    Spacer()
                }
                Spacer()
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    Spacer().frame(height: 56)

                    // Header
                    authHeader
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)

                    // Mode switcher (login / user / partner)
                    modeSwitcher
                        .opacity(appeared ? 1 : 0)

                    // Form
                    formFields
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 8)

                    // Error
                    if let err = errorMessage {
                        errorBanner(err)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Primary button
                    primaryButton
                        .opacity(appeared ? 1 : 0)

                    // Divider + Apple Sign In (not shown for partner join)
                    if mode != .partnerJoin {
                        divider
                        appleSignIn
                    }

                    // Footer
                    footerLinks
                        .opacity(appeared ? 1 : 0)

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 28)
                .animation(.easeInOut(duration: 0.22), value: mode)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Header
    private var authHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(colors: accentGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: accent.opacity(0.35), radius: 16, y: 5)
                Image(systemName: headerIcon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 6) {
                Text(headerTitle)
                    .font(.display(26))
                    .foregroundColor(.ink)
                Text(headerSubtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var headerIcon: String {
        switch mode {
        case .login:       return "person.fill"
        case .signup:      return "figure.run"
        case .partnerJoin: return "person.2.fill"
        }
    }

    private var headerTitle: String {
        switch mode {
        case .login:       return "Welcome Back"
        case .signup:      return "Create Account"
        case .partnerJoin: return "Join as Partner"
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .login:
            return "Sign in to check your progress and\nmanage your shield."
        case .signup:
            return "Start earning your screen time today.\nYour health data never leaves this device."
        case .partnerJoin:
            return "Your accountability role: monitor progress,\nhold the override code, keep them honest."
        }
    }

    // MARK: - Mode Switcher
    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            modeTab("Sign In",  for: .login)
            modeTab("User",     for: .signup)
            modeTab("Partner",  for: .partnerJoin)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
        )
    }

    private func modeTab(_ title: String, for tabMode: AuthMode) -> some View {
        let isActive = mode == tabMode
        let tabAccent: Color = .deepTeal
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                mode = tabMode
                errorMessage = nil
                clearForm()
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: isActive ? .bold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    isActive
                        ? RoundedRectangle(cornerRadius: 11).fill(tabAccent)
                        : RoundedRectangle(cornerRadius: 11).fill(Color.clear)
                )
                .foregroundColor(isActive ? .white : .muted)
                .padding(3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Form
    @ViewBuilder
    private var formFields: some View {
        VStack(spacing: 14) {
            // Display name (signup + partner)
            if mode == .signup || mode == .partnerJoin {
                AuthTextField(
                    icon: "person.fill",
                    placeholder: mode == .partnerJoin ? "Your Name" : "Display Name",
                    text: $displayName,
                    accentColor: accent
                )
            }

            // Email
            AuthTextField(
                icon: "envelope.fill",
                placeholder: "Email Address",
                text: $email,
                keyboardType: .emailAddress,
                accentColor: accent
            )

            // Password
            AuthSecureField(
                icon: "lock.fill",
                placeholder: "Password",
                text: $password,
                showPassword: $showPassword,
                accentColor: accent
            )

            // Confirm password (signup only)
            if mode == .signup {
                AuthSecureField(
                    icon: "lock.rotation",
                    placeholder: "Confirm Password",
                    text: $confirmPassword,
                    showPassword: $showPassword,
                    accentColor: accent
                )
            }

            // Partner invitation code
            if mode == .partnerJoin {
                partnerCodeSection
            }

            // Terms (signup only)
            if mode == .signup {
                termsRow
            }
        }
    }

    private var partnerCodeSection: some View {
        VStack(spacing: 10) {
            AuthTextField(
                icon: "key.fill",
                placeholder: "Invitation Code (from your partner)",
                text: $partnerCode,
                accentColor: accent
            )

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.deepTeal)
                    .font(.system(size: 13))
                    .padding(.top, 1)
                Text("Your partner shares this code from Settings → Pairing. It links your accounts for mutual accountability.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.deepTeal.opacity(0.08))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.deepTeal.opacity(0.2), lineWidth: 1))
        }
    }

    private var termsRow: some View {
        Button(action: { agreedToTerms.toggle() }) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                    .foregroundColor(agreedToTerms ? .deepTeal : .muted)
                    .font(.title3)
                Text("I agree to the Terms of Service and Privacy Policy. My health data stays on-device and is never uploaded.")
                    .font(.system(size: 12))
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error Banner
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption)
            Text(message).font(.caption)
        }
        .foregroundColor(Color(hex: "#FF6B6B"))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#FF6B6B").opacity(0.10))
        .cornerRadius(12)
    }

    // MARK: - Primary Button
    private var primaryButton: some View {
        Button(action: handleAuth) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white).scaleEffect(0.9)
                } else {
                    Image(systemName: actionIcon).font(.body.weight(.semibold))
                    Text(actionTitle).fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(
                isFormValid
                    ? LinearGradient(colors: accentGradient, startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color.muted.opacity(0.25), Color.muted.opacity(0.2)],
                                     startPoint: .leading, endPoint: .trailing)
            )
            .foregroundColor(isFormValid ? .white : .muted)
            .cornerRadius(16)
            .shadow(color: isFormValid ? accent.opacity(0.3) : .clear, radius: 12, y: 4)
        }
        .disabled(!isFormValid || isLoading)
    }

    private var actionIcon: String {
        switch mode {
        case .login:       return "arrow.right.circle.fill"
        case .signup:      return "person.badge.plus"
        case .partnerJoin: return "person.2.circle.fill"
        }
    }

    private var actionTitle: String {
        switch mode {
        case .login:       return "Sign In"
        case .signup:      return "Create Account"
        case .partnerJoin: return "Join as Partner"
        }
    }

    private var isFormValid: Bool {
        switch mode {
        case .login:
            return !email.isEmpty && password.count >= 6
        case .signup:
            return !displayName.isEmpty && !email.isEmpty && password.count >= 6
                && password == confirmPassword && agreedToTerms
        case .partnerJoin:
            return !displayName.isEmpty && !email.isEmpty && password.count >= 6
                && !partnerCode.isEmpty
        }
    }

    // MARK: - Divider
    private var divider: some View {
        HStack {
            Rectangle().fill(Color.muted.opacity(0.3)).frame(height: 1)
            Text("or").font(.caption).foregroundColor(.muted).padding(.horizontal, 12)
            Rectangle().fill(Color.muted.opacity(0.3)).frame(height: 1)
        }
    }

    // MARK: - Apple Sign In
    private var appleSignIn: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.email, .fullName]
        } onCompletion: { result in
            handleAppleSignIn(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 54)
        .cornerRadius(16)
    }

    // MARK: - Footer
    private var footerLinks: some View {
        VStack(spacing: 10) {
            if mode == .login {
                Button("Forgot Password?") { }
                    .font(.subheadline)
                    .foregroundColor(.muted)
            }

            HStack(spacing: 4) {
                Text(mode == .login ? "New here?" : "Already have an account?")
                    .font(.subheadline)
                    .foregroundColor(.muted)
                Button(mode == .login ? "Create Account" : "Sign In") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = mode == .login ? .signup : .login
                        errorMessage = nil
                        clearForm()
                    }
                }
                .font(.subheadline.weight(.bold))
                .foregroundColor(accent)
            }
        }
    }

    // MARK: - Helpers
    private func clearForm() {
        email = ""; password = ""; confirmPassword = ""
        displayName = ""; partnerCode = ""; agreedToTerms = false
    }

    // MARK: - Auth Handler (simulated — replace with real auth service)
    private func handleAuth() {
        isLoading = true
        errorMessage = nil

        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)

            await MainActor.run {
                isLoading = false

                var profile = UserProfile.placeholder
                profile.displayName = mode == .login
                    ? (email.components(separatedBy: "@").first ?? "User")
                    : displayName
                onboardingVM.userProfile = profile

                switch mode {
                case .login:
                    if UserDefaults.standard.bool(forKey: "onboarding_complete") {
                        onboardingVM.isOnboardingComplete = true
                    }

                case .signup:
                    break // Onboarding will run after auth

                case .partnerJoin:
                    onboardingVM.currentStep = .pairing
                }

                UserDefaults.standard.set(true, forKey: "is_authenticated")
                dismiss()
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }.joined(separator: " ")
                var profile = UserProfile.placeholder
                profile.displayName = name.isEmpty ? "User" : name
                onboardingVM.userProfile = profile
                UserDefaults.standard.set(true, forKey: "is_authenticated")
                dismiss()
            }
        case .failure(let error):
            errorMessage = "Apple Sign In failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Custom Text Field
struct AuthTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var accentColor: Color = .deepTeal

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(isFocused ? accentColor : .muted)
                .frame(width: 20)

            TextField("", text: $text,
                      prompt: Text(placeholder).foregroundColor(.muted))
                .foregroundColor(.ink)
                .font(.body)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.ink.opacity(isFocused ? 0.04 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isFocused ? accentColor.opacity(0.5) : Color.white.opacity(0.6), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}

// MARK: - Custom Secure Field
struct AuthSecureField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool
    var accentColor: Color = .deepTeal

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(isFocused ? accentColor : .muted)
                .frame(width: 20)

            Group {
                if showPassword {
                    TextField("", text: $text,
                              prompt: Text(placeholder).foregroundColor(.muted))
                } else {
                    SecureField("", text: $text,
                                prompt: Text(placeholder).foregroundColor(.muted))
                }
            }
            .foregroundColor(.ink)
            .font(.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isFocused)

            Button(action: { showPassword.toggle() }) {
                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.muted)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.ink.opacity(isFocused ? 0.04 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isFocused ? accentColor.opacity(0.5) : Color.white.opacity(0.6), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}

#Preview("User Login") {
    AuthView(initialMode: .login)
        .environmentObject(OnboardingViewModel())
}

#Preview("Partner Join") {
    AuthView(initialMode: .partnerJoin)
        .environmentObject(OnboardingViewModel())
}
