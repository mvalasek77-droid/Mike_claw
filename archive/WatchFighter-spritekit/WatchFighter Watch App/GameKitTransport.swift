#if os(watchOS)
import Foundation

/// Online-versus transport stub.
///
/// IMPORTANT: real-time GameKit (`GKMatch` / `GKMatchmaker`) is **not available
/// on watchOS** — those APIs are iOS/macOS/tvOS only. True Watch-to-Watch play
/// therefore has to be relayed through a companion iPhone (WatchConnectivity +
/// the phone's GameKit/Network stack), which is a roadmap item.
///
/// This stub keeps the `MatchTransport` architecture intact (the deterministic
/// lockstep netcode, `VersusMatchup`, and `LoopbackTransport` are real and
/// unit-tested) and reports a clear "coming soon" message instead of calling
/// APIs that don't exist on the watch. No soft-lock: the lobby's BACK button
/// always works.
final class GameKitTransport: MatchTransport {
    var onReceive: ((NetMessage) -> Void)?
    var onDisconnect: (() -> Void)?
    var onConnected: ((Side) -> Void)?
    var onError: ((String) -> Void)?

    func authenticate(completion: @escaping (Bool) -> Void) { completion(true) }

    func findMatch() {
        onError?("Online Versus needs the companion iPhone app — coming soon. Story, Training and the netcode core all work today.")
    }

    func send(_ message: NetMessage) { /* no-op until iPhone relay lands */ }
    func disconnect() { onDisconnect?() }
}
#endif
