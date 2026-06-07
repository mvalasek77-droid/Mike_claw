import Foundation

/// One tick's worth of a player's inputs, exchanged over the wire. `Codable`
/// so any transport (GameKit, Watch Connectivity, loopback) can serialise it.
struct InputFrame: Equatable, Codable {
    let tick: Int
    let intents: [Intent]
}

/// Deterministic input-delay lockstep. Each side buffers its own inputs and the
/// remote's; a tick may only advance once both sides' frames for that tick have
/// arrived. Inputs entered now apply `inputDelay` ticks later, giving the
/// network time to deliver them without stalling.
///
/// The combat simulation is deterministic (no RNG on the PvP path), so feeding
/// both sides identical inputs keeps the two watches perfectly in sync.
final class LockstepSession {
    let localSide: Side
    let inputDelay: Int

    private(set) var currentTick = 0
    private var local: [Int: [Intent]] = [:]
    private var remote: [Int: [Intent]] = [:]
    private var nextSubmitTick: Int

    init(localSide: Side, inputDelay: Int = 2) {
        self.localSide = localSide
        self.inputDelay = max(1, inputDelay)
        self.nextSubmitTick = self.inputDelay
        // Pre-fill the delay window with empty inputs so the first ticks run.
        for t in 0..<self.inputDelay {
            local[t] = []
            remote[t] = []
        }
    }

    /// Queue this tick's local intents and return the frame to transmit. Each
    /// call advances the submit cursor so frames are produced once per send.
    func submitLocal(_ intents: [Intent]) -> InputFrame {
        let applyTick = nextSubmitTick
        nextSubmitTick += 1
        local[applyTick] = intents
        return InputFrame(tick: applyTick, intents: intents)
    }

    /// Record a frame received from the peer.
    func receiveRemote(_ frame: InputFrame) {
        remote[frame.tick] = frame.intents
    }

    /// Both sides' inputs for the current tick are present.
    var canAdvance: Bool {
        local[currentTick] != nil && remote[currentTick] != nil
    }

    /// Resolve which side's inputs map to player vs opponent for `currentTick`.
    /// Returns (playerIntents, opponentIntents) and advances the tick.
    func consumeCurrentTick() -> (player: [Intent], opponent: [Intent])? {
        guard canAdvance else { return nil }
        let localIntents = local[currentTick] ?? []
        let remoteIntents = remote[currentTick] ?? []
        local[currentTick] = nil
        remote[currentTick] = nil
        currentTick += 1
        // Side mapping: the local fighter is always `.player` on this device.
        if localSide == .player {
            return (localIntents, remoteIntents)
        } else {
            return (remoteIntents, localIntents)
        }
    }
}

/// Abstracts the wire so the netplay layer doesn't care whether frames travel
/// over GameKit, Watch Connectivity, or an in-process loopback.
protocol MatchTransport: AnyObject {
    var onReceiveFrame: ((InputFrame) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    func send(_ frame: InputFrame)
    func disconnect()
}

extension MatchTransport {
    /// Convenience: encode/decode `InputFrame` to `Data` for byte-based transports.
    func encode(_ frame: InputFrame) -> Data? { try? JSONEncoder().encode(frame) }
    func decodeFrame(_ data: Data) -> InputFrame? { try? JSONDecoder().decode(InputFrame.self, from: data) }
}

/// In-process transport that delivers frames straight to a paired instance.
/// Used for tests and a single-device demo; also a reference for real transports.
final class LoopbackTransport: MatchTransport {
    var onReceiveFrame: ((InputFrame) -> Void)?
    var onDisconnect: (() -> Void)?
    weak var peer: LoopbackTransport?

    func send(_ frame: InputFrame) { peer?.onReceiveFrame?(frame) }
    func disconnect() { onDisconnect?(); peer?.onDisconnect?() }

    /// Wire two endpoints together.
    static func pair() -> (LoopbackTransport, LoopbackTransport) {
        let a = LoopbackTransport(), b = LoopbackTransport()
        a.peer = b; b.peer = a
        return (a, b)
    }
}
