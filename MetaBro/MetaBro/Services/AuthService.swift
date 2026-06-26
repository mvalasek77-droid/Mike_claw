import Foundation

enum AuthError: Error, Equatable {
    /// Doesn't satisfy `OnboardingDraft.isValid` (length/characters/empty name).
    case invalidHandle
    /// Someone already claimed this handle.
    case handleTaken
}

/// Pure data operations — none of these touch `Session`. The caller (the
/// launch flow, onboarding) decides when to sign `Session` in/out, so the
/// service stays simple to unit test without mutating global app state.
protocol AuthService: Sendable {
    /// Restores a previously-completed identity, if one was persisted from an
    /// earlier launch.
    func restoreSession() async -> User?
    /// Completes onboarding: claims the handle, creates the identity, and
    /// persists it.
    func completeOnboarding(_ draft: OnboardingDraft) async throws -> User
    /// Clears the persisted identity.
    func signOut() async
}

/// Offline-friendly backend: persists the claimed identity to `UserDefaults`
/// so it survives relaunch, with no server required. Handle uniqueness isn't
/// enforceable without a backend, so every well-formed handle is accepted.
actor MockAuthService: AuthService {
    private let defaults: UserDefaults
    private let idKey = "metabro.session.id"
    private let handleKey = "metabro.session.handle"
    private let nameKey = "metabro.session.displayName"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restoreSession() async -> User? {
        guard let idString = defaults.string(forKey: idKey),
              let id = UUID(uuidString: idString),
              let handle = defaults.string(forKey: handleKey),
              let name = defaults.string(forKey: nameKey) else { return nil }
        let user = User(id: id, handle: handle, displayName: name, avatarURL: nil, broCred: 0)
        return user
    }

    func completeOnboarding(_ draft: OnboardingDraft) async throws -> User {
        guard draft.isValid else { throw AuthError.invalidHandle }
        try await Task.sleep(nanoseconds: 300_000_000) // simulated round trip
        let user = User(
            id: UUID(),
            handle: "@\(draft.handle.trimmingCharacters(in: .whitespacesAndNewlines))",
            displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarURL: nil,
            broCred: 0
        )
        defaults.set(user.id.uuidString, forKey: idKey)
        defaults.set(user.handle, forKey: handleKey)
        defaults.set(user.displayName, forKey: nameKey)
        return user
    }

    func signOut() async {
        defaults.removeObject(forKey: idKey)
        defaults.removeObject(forKey: handleKey)
        defaults.removeObject(forKey: nameKey)
    }
}
