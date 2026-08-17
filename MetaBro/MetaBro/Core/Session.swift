import Foundation
import Synchronization

/// The signed-in identity. A single source of truth so composer-authored posts,
/// the profile screen, and "OP" highlighting all agree on who "you" are.
///
/// Starts as `guest` (no real identity yet) until onboarding completes or a
/// persisted session is restored; `AuthService` is the only thing that should
/// call `signIn`/`signOut`. Backed by `Mutex` (not a lock type) so `Session.me`
/// stays a plain, synchronous read callable from any isolation domain —
/// actors, `@MainActor` view models, and plain model code alike.
final class Session: Sendable {
    /// The instance the running app uses everywhere. Tests that need to
    /// exercise sign-in/out should construct their own `Session()` instead —
    /// it's process-wide mutable state, so sharing it across concurrently
    /// running test suites would make assertions on `Session.me` flaky.
    static let shared = Session()

    /// The pre-onboarding placeholder identity. Distinguishable from any real
    /// account so `isSignedIn` is exact, not heuristic.
    static let guest = User(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B0")!,
        handle: "@guest",
        displayName: "Guest",
        avatarURL: nil,
        broCred: 0
    )

    private let state = Mutex(Session.guest)

    init() {}

    var current: User { state.withLock { $0 } }
    var isSignedIn: Bool { state.withLock { $0.id != Session.guest.id } }

    func signIn(as user: User) { state.withLock { $0 = user } }
    func signOut() { state.withLock { $0 = Session.guest } }

    /// Convenience read used throughout the app: `Session.me`.
    static var me: User { shared.current }
}
