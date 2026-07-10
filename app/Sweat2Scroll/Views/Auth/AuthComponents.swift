// Views/Auth/AuthComponents.swift
// Shared building blocks for the Sign Up / Sign In screens so both stay
// visually identical: primary CTA, "or" divider, Google + Apple buttons,
// and friendly Apple-auth error mapping.

import SwiftUI
import AuthenticationServices

// MARK: - Primary CTA used by auth screens

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
                    ? LinearGradient(colors: [.deepTeal, Color(hex: "#1A7A90")],
                                     startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color.muted.opacity(0.25), Color.muted.opacity(0.2)],
                                     startPoint: .leading, endPoint: .trailing)
            )
            .foregroundColor(isEnabled ? .white : .muted)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: isEnabled ? Color.deepTeal.opacity(0.25) : .clear, radius: 12, y: 4)
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

// MARK: - "or" divider

struct AuthDividerOr: View {
    var body: some View {
        HStack {
            Rectangle().fill(Color.muted.opacity(0.25)).frame(height: 1)
            Text("or").font(.caption).foregroundColor(.muted).padding(.horizontal, 10)
            Rectangle().fill(Color.muted.opacity(0.25)).frame(height: 1)
        }
    }
}

// MARK: - Google + Apple buttons

struct AuthSocialButtons: View {
    enum Context { case signIn, signUp }

    let context: Context
    @Binding var showGoogleSoon: Bool
    /// When provided, taps run the real Google Sign-In flow; otherwise the
    /// legacy "coming soon" alert (`showGoogleSoon`) is shown.
    var onGoogle: (() -> Void)? = nil
    let onAppleResult: (Result<ASAuthorization, Error>) -> Void

    private var idPrefix: String { context == .signIn ? "signIn" : "signUp" }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                if let onGoogle { onGoogle() } else { showGoogleSoon = true }
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
            .accessibilityIdentifier("\(idPrefix).google")

            SignInWithAppleButton(context == .signIn ? .signIn : .signUp) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                onAppleResult(result)
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
            .accessibilityIdentifier("\(idPrefix).apple")
        }
    }
}

// MARK: - Apple auth error mapping

enum AuthUX {
    /// Maps `ASAuthorizationError` (e.g. 1000 unknown → missing capability) to actionable copy.
    static func friendlyAuthError(_ error: Error) -> String {
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
}
