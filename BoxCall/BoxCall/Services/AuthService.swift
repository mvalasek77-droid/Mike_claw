import Foundation
import AuthenticationServices
import Combine

/// Sign in with Apple + guest mode. Persists the credential the OS
/// hands back and hydrates User.handle / User.appleUserId. Guest
/// state stays fully functional — sign-in is optional and buys you
/// cloud sync (once the backend exists) rather than gating gameplay.
@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published private(set) var appleUserId: String?
    @Published private(set) var signedInEmail: String?
    @Published private(set) var lastError: String?
    @Published var signInInFlight: Bool = false

    private let userIdKey = "auth.appleUserId"
    private let emailKey  = "auth.email"

    var isSignedIn: Bool { appleUserId != nil }

    override init() {
        super.init()
        appleUserId = UserDefaults.standard.string(forKey: userIdKey)
        signedInEmail = UserDefaults.standard.string(forKey: emailKey)
        if let uid = appleUserId {
            PortfolioService.shared.mutateUser { $0.appleUserId = uid }
        }
        checkExistingCredential()
    }

    // MARK: - Sign in with Apple

    /// Called by the SwiftUI `SignInWithAppleButton` when the OS hands
    /// back a credential.
    func startSignInFromResult(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            recordError("Unknown credential type."); return
        }
        let uid = credential.user
        let email = credential.email
        let display = credential.fullName?.givenName?.lowercased()
        appleUserId = uid
        signedInEmail = email
        lastError = nil
        UserDefaults.standard.set(uid, forKey: userIdKey)
        // Apple returns the email only on the very first authorization.
        // Overwriting with nil on a later sign-in would lose it.
        if let email { UserDefaults.standard.set(email, forKey: emailKey) }
        PortfolioService.shared.mutateUser { u in
            u.appleUserId = uid
            if let display, !display.isEmpty, u.handle == "you" { u.handle = display }
        }
        signInInFlight = false
    }

    /// Turns an authorization failure into something a person can act on.
    ///
    /// The raw `localizedDescription` for the most common failure is
    /// "The operation couldn't be completed. (…AuthorizationError error
    /// 1000.)", which tells nobody anything. Code 1000 almost always
    /// means the build is missing the Sign in with Apple entitlement or
    /// the App ID does not have the capability enabled.
    func handleSignInFailure(_ error: Error) {
        signInInFlight = false

        guard let authError = error as? ASAuthorizationError else {
            lastError = error.localizedDescription
            return
        }

        switch authError.code {
        case .canceled:
            // Backing out is not a failure. Showing red text for it
            // makes a working button look broken.
            lastError = nil
        case .unknown:
            lastError = "Sign in with Apple isn't available in this build. "
                + "Check that the app is signed with the Sign in with Apple "
                + "entitlement and that you're signed into iCloud on this device."
        case .notHandled:
            lastError = "Sign in with Apple couldn't complete. Make sure you're signed into iCloud in Settings."
        case .invalidResponse:
            lastError = "Apple returned an unexpected response. Please try again."
        case .failed:
            lastError = "Apple couldn't verify that request. Please try again."
        case .notInteractive:
            lastError = "Sign in needs the app to be in the foreground."
        @unknown default:
            lastError = error.localizedDescription
        }
    }

    func recordError(_ msg: String) {
        lastError = msg
        signInInFlight = false
    }

    /// Set when the button is tapped so the card can show progress and
    /// stop a second tap racing the first.
    func beginSignIn() {
        signInInFlight = true
        lastError = nil
    }

    func signOut() {
        appleUserId = nil
        signedInEmail = nil
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
        PortfolioService.shared.mutateUser { $0.appleUserId = nil }
        AnalyticsService.shared.track(.signOut)
    }

    private func checkExistingCredential() {
        guard let uid = appleUserId else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: uid) { [weak self] state, _ in
            Task { @MainActor in
                if case .revoked = state { self?.signOut() }
                if case .notFound = state { self?.signOut() }
            }
        }
    }
}

// The UIKit delegate path that used to live here has been removed.
// It was never called — `AuthCard` uses SwiftUI's
// `SignInWithAppleButton`, which owns the controller and returns the
// credential through its own completion handler. The old code also built
// its `ASAuthorizationController` as a local that went out of scope the
// moment `performRequests()` returned, so it could not reliably have
// worked had anything called it.
