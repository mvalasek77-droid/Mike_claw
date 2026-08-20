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

    func startSignInWithApple() {
        signInInFlight = true
        lastError = nil
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    /// SwiftUI's SignInWithAppleButton returns the credential directly;
    /// this lets AuthCard hand it back to us without a separate delegate.
    func startSignInFromResult(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            recordError("Unknown credential type."); return
        }
        let uid = credential.user
        let email = credential.email
        let display = credential.fullName?.givenName?.lowercased()
        self.appleUserId = uid
        self.signedInEmail = email
        UserDefaults.standard.set(uid, forKey: self.userIdKey)
        if let email { UserDefaults.standard.set(email, forKey: self.emailKey) }
        PortfolioService.shared.mutateUser { u in
            u.appleUserId = uid
            if let display, !display.isEmpty, u.handle == "you" { u.handle = display }
        }
        self.signInInFlight = false
    }

    func recordError(_ msg: String) {
        self.lastError = msg
        self.signInInFlight = false
    }

    func signOut() {
        appleUserId = nil
        signedInEmail = nil
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
        PortfolioService.shared.mutateUser { $0.appleUserId = nil }
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

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate,
                       ASAuthorizationControllerPresentationContextProviding {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization auth: ASAuthorization
    ) {
        guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
        let uid = credential.user
        let email = credential.email
        let display: String? = credential.fullName?.givenName?.lowercased()
        Task { @MainActor in
            self.appleUserId = uid
            self.signedInEmail = email
            UserDefaults.standard.set(uid, forKey: self.userIdKey)
            if let email { UserDefaults.standard.set(email, forKey: self.emailKey) }
            PortfolioService.shared.mutateUser { u in
                u.appleUserId = uid
                if let display, !display.isEmpty, u.handle == "you" { u.handle = display }
            }
            self.signInInFlight = false
            // TODO: sync positions + XP to backend once /me endpoint exists.
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.signInInFlight = false
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController)
        -> ASPresentationAnchor {
        // A window from any connected foreground scene will do.
        for scene in UIApplication.shared.connectedScenes {
            if let ws = scene as? UIWindowScene,
               let w = ws.windows.first(where: \.isKeyWindow) ?? ws.windows.first {
                return w
            }
        }
        return ASPresentationAnchor()
    }
}

#if canImport(UIKit)
import UIKit
#endif
