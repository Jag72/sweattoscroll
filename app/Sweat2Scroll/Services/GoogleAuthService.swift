// Services/GoogleAuthService.swift
// Thin wrapper around the GoogleSignIn-iOS SDK. Everything that touches the SDK
// is behind `#if canImport(GoogleSignIn)` so the project keeps compiling before
// the package is added in Xcode (File → Add Package Dependencies →
// https://github.com/google/GoogleSignIn-iOS → add the "GoogleSignIn" product).
//
// The iOS OAuth client ID is read from Info.plist key `GIDClientID`, and the
// reversed client ID must be registered as a URL scheme (also in Info.plist).

import Foundation
import UIKit

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@MainActor
final class GoogleAuthService {
    static let shared = GoogleAuthService()
    private init() {}

    /// Minimal, SDK-agnostic profile handed back to `AuthManager`.
    struct Profile {
        let userID: String
        let email: String?
        let fullName: String?
    }

    enum GoogleAuthError: LocalizedError {
        case notConfigured
        case sdkMissing
        case noPresenter
        case missingProfile
        /// User dismissed the Google sheet or the system consent dialog.
        /// Callers should treat this as a no-op, NOT display it as an error.
        case canceled

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Google Sign-In isn't configured. Add your GIDClientID to Info.plist."
            case .sdkMissing:
                return "Google Sign-In needs the GoogleSignIn package. In Xcode: File → Add Package Dependencies → github.com/google/GoogleSignIn-iOS."
            case .noPresenter:
                return "Couldn't present Google Sign-In. Please try again."
            case .missingProfile:
                return "Google didn't return your account details. Please try again."
            case .canceled:
                return "Sign-in canceled."
            }
        }
    }

    /// iOS OAuth client ID, read from Info.plist (`GIDClientID`).
    static var clientID: String? {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
    }

    /// Whether Google Sign-In can actually run in this build (SDK present + client ID set).
    var isAvailable: Bool {
        #if canImport(GoogleSignIn)
        return Self.clientID?.isEmpty == false
        #else
        return false
        #endif
    }

    /// Must be called from the app's `onOpenURL` so the SDK can complete the
    /// OAuth redirect. Returns true if the URL was a Google Sign-In callback.
    @discardableResult
    static func handleURL(_ url: URL) -> Bool {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }

    /// Presents the Google Sign-In sheet and returns the signed-in profile.
    func signIn() async throws -> Profile {
        #if canImport(GoogleSignIn)
        guard let clientID = Self.clientID, !clientID.isEmpty else {
            throw GoogleAuthError.notConfigured
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let presenter = Self.topViewController() else {
            throw GoogleAuthError.noPresenter
        }

        // Returning Google user on this device? Restore silently — no browser
        // sheet, no "Wants to Use google.com" dialog. Falls through to the
        // interactive flow if restore fails (revoked, expired, first run).
        if GIDSignIn.sharedInstance.hasPreviousSignIn(),
           let restored = try? await GIDSignIn.sharedInstance.restorePreviousSignIn(),
           let restoredID = restored.userID {
            return Profile(
                userID: restoredID,
                email: restored.profile?.email,
                fullName: restored.profile?.name
            )
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            let user = result.user
            guard let userID = user.userID else { throw GoogleAuthError.missingProfile }
            return Profile(
                userID: userID,
                email: user.profile?.email,
                fullName: user.profile?.name
            )
        } catch let error as GIDSignInError where error.code == .canceled {
            throw GoogleAuthError.canceled
        }
        #else
        throw GoogleAuthError.sdkMissing
        #endif
    }

    /// Clears the cached Google session (best-effort; safe if SDK absent).
    func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
    }

    // MARK: - Presenter discovery

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let baseVC = base ?? keyWindow()?.rootViewController
        if let nav = baseVC as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = baseVC as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = baseVC?.presentedViewController {
            return topViewController(base: presented)
        }
        return baseVC
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
