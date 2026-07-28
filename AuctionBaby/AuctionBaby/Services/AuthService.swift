import Foundation
import AuthenticationServices

/// Owns the app's authenticated server identity: the `serverUserId` and the
/// session token issued by the auth Worker after a successful Sign in with
/// Apple exchange. Both live in the Keychain (via `SecureStore`) — never in
/// UserDefaults — because they're auth credentials.
///
/// This is Slice 1 of the spine (see `SPINE_ROADMAP.md`). It is deliberately
/// **additive**: the on-device profile in `AuctionStore.me` remains the source
/// of truth for the UI; this service just carries the extra "who this user is
/// on our server" facts that later slices (push, matching, moderation) will
/// need. Demo Mode and the local-only onboarding path continue to work
/// identically whether or not a server session is present.
///
/// Absent config (`BackendConfig.authURL` empty) → the service is `disabled`
/// and every call is a no-op that reports `.notConfigured`.
@MainActor
final class AuthService: ObservableObject {
    /// The user's stable id on our server. Present iff signed in.
    @Published private(set) var serverUserId: String?
    /// The signed-in user's server-side profile (email, name, dob). Cached
    /// from the last `/me` fetch; hydrated at launch and refreshed after
    /// sign-in.
    @Published private(set) var user: RemoteUser?
    /// True while a network call (sign-in, /me, delete) is in flight.
    @Published private(set) var inFlight = false
    /// The last error string surfaced to the UI. Cleared on the next attempt.
    @Published var lastError: String?

    /// Called after a successful `signOut()` (or `deleteAccount()`), *after*
    /// the local Keychain state has been cleared. Wired at app root so
    /// PushService can unregister its APNs token without importing us.
    var onSignedOut: (() async -> Void)?

    private var sessionToken: String? {
        get { SecureStore.string(forKey: Self.tokenKey) }
        set { SecureStore.setString(newValue, forKey: Self.tokenKey) }
    }

    private static let tokenKey = "com.valasek.auctionbaby.auth.sessionToken.v1"
    private static let userIdKey = "com.valasek.auctionbaby.auth.serverUserId.v1"

    /// True iff an auth Worker URL is bundled with the build. When false, the
    /// SIWA button hides and the app runs in local-only mode.
    var isEnabled: Bool { !BackendConfig.authURL.isEmpty }

    /// True iff a session token is present. The token isn't cryptographically
    /// verified locally — only the server can do that — so this is a "we
    /// think we're signed in" flag, not a guarantee. Call `refreshMe()` to
    /// confirm and drop the session on 401.
    var isSignedIn: Bool { sessionToken != nil && serverUserId != nil }

    init() {
        // Rehydrate the userId at launch so views observe the right state
        // before the first network call.
        self.serverUserId = SecureStore.string(forKey: Self.userIdKey)
    }

    // MARK: - Public API

    /// Hand off the identity token from a completed `ASAuthorizationAppleIDCredential`
    /// to the auth Worker, receive a session, and store it.
    ///
    /// `name` comes from `credential.fullName` — Apple only returns it on the
    /// FIRST sign-in for a given Apple ID + team, so if the user was here
    /// before we'll pass nil and the server keeps whatever it already has.
    @discardableResult
    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential) async -> AuthResult {
        guard isEnabled else { return .notConfigured }
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            return .failure("Apple didn't return an identity token — try again.")
        }
        let displayName = fullNameString(credential.fullName)

        inFlight = true
        defer { inFlight = false }
        lastError = nil

        struct Body: Encodable { let identityToken: String; let name: String? }
        struct Response: Decodable { let userId: String; let sessionToken: String; let isNew: Bool; let user: RemoteUser }

        switch await request("/auth/apple", method: "POST",
                              body: Body(identityToken: identityToken, name: displayName),
                              auth: false, as: Response.self) {
        case .success(let r):
            self.sessionToken = r.sessionToken
            SecureStore.setString(r.userId, forKey: Self.userIdKey)
            self.serverUserId = r.userId
            self.user = r.user
            return .success(isNew: r.isNew, user: r.user)
        case .failure(let message):
            self.lastError = message
            return .failure(message)
        }
    }

    /// Refresh the server-side user record. Drops the local session on 401 so
    /// a rotated `SESSION_SECRET` (or a deleted account) doesn't leave the app
    /// in a phantom-signed-in state.
    @discardableResult
    func refreshMe() async -> Bool {
        guard isEnabled, sessionToken != nil else { return false }
        struct Response: Decodable { let user: RemoteUser }
        switch await request("/me", method: "GET", body: EmptyBody?.none,
                              auth: true, as: Response.self) {
        case .success(let r):
            self.user = r.user
            self.serverUserId = r.user.id
            SecureStore.setString(r.user.id, forKey: Self.userIdKey)
            return true
        case .failure(let message):
            // Any auth failure => discard the session locally so the user
            // ends up on the sign-in flow instead of a broken signed-in one.
            if message.contains("Unauthorized") || message.contains("401") {
                signOutLocally()
            }
            return false
        }
    }

    /// Sign out on this device (no server-side revocation in slice 1 — see
    /// the Worker's README on stateless-session tradeoffs). The `onSignedOut`
    /// hook fires AFTER local state is cleared, so callers like PushService
    /// can do their own cleanup with the session still readable.
    func signOut() async {
        // Push-service unregister runs while the session is still valid, so it
        // can authenticate the DELETE. Do this before clearing the token.
        await onSignedOut?()
        // Best-effort ping; ignore failures. What matters is the local drop.
        if isEnabled, sessionToken != nil {
            _ = await request("/auth/logout", method: "POST", body: EmptyBody?.none,
                              auth: true, as: EmptyResponse.self)
        }
        signOutLocally()
    }

    /// Hard-delete the account server-side (GDPR/CCPA subject-delete). Client
    /// state is cleared regardless of the network result — we never want to
    /// leave the user "signed in but their record is gone."
    @discardableResult
    func deleteAccount() async -> Bool {
        await onSignedOut?()
        guard isEnabled, sessionToken != nil else { signOutLocally(); return true }
        let result = await request("/me", method: "DELETE", body: EmptyBody?.none,
                                    auth: true, as: EmptyResponse.self)
        signOutLocally()
        if case .failure(let m) = result { self.lastError = m; return false }
        return true
    }

    // MARK: - Internals

    private func signOutLocally() {
        SecureStore.setString(nil, forKey: Self.tokenKey)
        SecureStore.setString(nil, forKey: Self.userIdKey)
        self.serverUserId = nil
        self.user = nil
    }

    private func fullNameString(_ n: PersonNameComponents?) -> String? {
        guard let n else { return nil }
        let f = PersonNameComponentsFormatter()
        f.style = .default
        let s = f.string(from: n).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    private struct EmptyBody: Encodable {}
    private struct EmptyResponse: Decodable {}

    private enum TransportResult<T: Decodable> {
        case success(T); case failure(String)
    }

    private func request<Body: Encodable, T: Decodable>(
        _ path: String, method: String, body: Body?, auth: Bool, as type: T.Type,
    ) async -> TransportResult<T> {
        let base = BackendConfig.authURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return .failure("Auth Worker not configured.") }
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: "\(trimmed)\(path)") else {
            return .failure("Auth Worker URL looks malformed.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        if auth, let token = sessionToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(body)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                struct WorkerError: Decodable { let error: String? }
                let decoded = try? JSONDecoder().decode(WorkerError.self, from: data)
                let message = decoded?.error ?? "HTTP \(status)"
                ErrorMonitor.shared.record(category: "Auth",
                                           message: "\(method) \(path) failed",
                                           detail: message)
                return .failure(message)
            }
            if T.self == EmptyResponse.self {
                return .success(EmptyResponse() as! T)
            }
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return .success(decoded)
        } catch {
            ErrorMonitor.shared.record(category: "Auth",
                                       message: "\(method) \(path) transport",
                                       detail: error.localizedDescription)
            return .failure(error.localizedDescription)
        }
    }
}

/// The public shape of a signed-in user, mirroring the Worker's `publicUser`.
/// Never includes Apple's `sub` (Apple's guideline) — only our internal id.
struct RemoteUser: Codable, Equatable {
    let id: String
    let email: String?
    let name: String?
    let dateOfBirth: String?
    let createdAt: Double
    let lastSeenAt: Double
}

/// Outcome of a Sign in with Apple attempt.
enum AuthResult {
    case success(isNew: Bool, user: RemoteUser)
    case failure(String)
    case notConfigured
}
