#if os(watchOS)
import GameKit

/// Real-time GameKit transport for Watch-to-Watch versus. Implements the
/// engine's `MatchTransport` so the netplay layer is identical whether running
/// over GameKit or the in-process `LoopbackTransport`.
///
/// NOTE (honesty): GameKit real-time matchmaking on watchOS is constrained and
/// requires Game Center entitlement + a signed build to actually connect. This
/// class is wired correctly against the API but is **untested on-device**; the
/// app degrades gracefully to an error state if authentication/matchmaking
/// fails so the rest of the game keeps working.
final class GameKitTransport: NSObject, MatchTransport, GKMatchDelegate {
    var onReceiveFrame: ((InputFrame) -> Void)?
    var onDisconnect: (() -> Void)?

    /// Called once both players are connected; provides the deterministic side
    /// assignment (lower playerID == `.player`) so both devices agree.
    var onConnected: ((Side) -> Void)?
    var onError: ((String) -> Void)?

    private var match: GKMatch?

    func authenticate(completion: @escaping (Bool) -> Void) {
        let local = GKLocalPlayer.local
        local.authenticateHandler = { _, error in
            completion(local.isAuthenticated && error == nil)
        }
    }

    func findMatch() {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        GKMatchmaker.shared().findMatch(for: request) { [weak self] match, error in
            guard let self else { return }
            if let error { self.onError?(error.localizedDescription); return }
            guard let match else { self.onError?("No match found"); return }
            self.match = match
            match.delegate = self
            self.resolveSidesIfReady()
        }
    }

    private func resolveSidesIfReady() {
        guard let match, match.expectedPlayerCount == 0 else { return }
        // Deterministic side assignment: sort gamePlayerIDs, index 0 -> player.
        let ids = (match.players.map { $0.gamePlayerID } + [GKLocalPlayer.local.gamePlayerID]).sorted()
        let side: Side = ids.first == GKLocalPlayer.local.gamePlayerID ? .player : .opponent
        onConnected?(side)
    }

    func send(_ frame: InputFrame) {
        guard let match, let data = encode(frame) else { return }
        try? match.sendData(toAllPlayers: data, with: .reliable)
    }

    func disconnect() {
        match?.disconnect()
        match = nil
        onDisconnect?()
    }

    // MARK: GKMatchDelegate

    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        if let frame = decodeFrame(data) { onReceiveFrame?(frame) }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        switch state {
        case .connected:    resolveSidesIfReady()
        case .disconnected: onDisconnect?()
        default: break
        }
    }

    func match(_ match: GKMatch, didFailWithError error: Error?) {
        onError?(error?.localizedDescription ?? "Match failed")
    }
}
#endif
