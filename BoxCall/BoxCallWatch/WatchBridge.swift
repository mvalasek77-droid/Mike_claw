import Foundation
import WatchConnectivity
import Combine

/// Bridge between the iPhone app and the watch UI.
///
/// ⚠️ Transport note: the iPhone and the Watch each have their OWN App
/// Group containers, even for the same group id — an app group is a
/// same-device sharing mechanism, NOT a transport. The ONLY way snapshot
/// data reaches this device is the WCSession payload
/// (`updateApplicationContext` on the iOS side). The received snapshot
/// is decoded here and re-persisted into the watch-side app group so
/// cold launches (and the complication extension process) can read it
/// without waiting for a new push.
final class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchBridge()

    // MARK: - Watch snapshot model

    struct PositionSnap: Codable, Identifiable {
        let id: String
        let movieTitle: String
        let movieEmoji: String
        let sideLabel: String
        let strikeMillions: Double
        let quantity: Int
        let entryPremium: Double
        let mark: Double
        let pnl: Double
        let isSettled: Bool
        let settledPayout: Double?
    }

    struct Snapshot: Codable {
        let updatedAt: Date

        let nextMovieTitle: String
        let nextMoviePoster: String
        let nextMovieOpensIn: Int

        let balance: Double
        let totalPnL: Double
        let positions: [PositionSnap]

        /// The most notable open position (largest absolute P&L) — mirrors the
        /// pre-rebuild "top position" fields the complication still displays.
        var topPosition: PositionSnap? {
            positions
                .filter { !$0.isSettled }
                .max { abs($0.pnl) < abs($1.pnl) }
        }

        var topPositionMovie: String? { topPosition?.movieTitle }
        var topPositionSideLabel: String? { topPosition?.sideLabel }
        var topPositionPnL: Double? { topPosition?.pnl }
    }

    @Published private(set) var snapshot: Snapshot?

    /// Snapshot cache. Prefers the watch-side app group (shares with the
    /// complication extension) but falls back to plain UserDefaults when
    /// the group isn't entitled yet — cold starts still work either way;
    /// the WCSession inbox is the real transport and needs no group.
    private static let appGroup = "group.com.boxcall.shared"
    private static let cacheKey = "watch.snapshot.v2"

    private var cacheDefaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroup) ?? .standard
    }

    override init() {
        super.init()
        loadFromCache()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Called on scenePhase == .active: drain the WCSession inbox
    /// (the iPhone may have pushed while this app wasn't running) and
    /// ask the iPhone for a fresh snapshot when it is reachable.
    func refresh() {
        ingest(WCSession.default.receivedApplicationContext)
        if WCSession.default.isReachable {
            requestSnapshot()
        }
    }

    /// Fire-and-forget poke: the iOS app's `didReceiveMessage` handler
    /// rebuilds and pushes a fresh snapshot in response.
    private func requestSnapshot() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": "snapshot"], replyHandler: nil, errorHandler: nil)
    }

    /// Decode the latest application context from the iPhone.
    private func ingest(_ ctx: [String: Any]) {
        if let data = ctx["snapshot"] as? Data,
           let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            apply(s)
        } else {
            loadFromCache()
        }
    }

    private func apply(_ s: Snapshot) {
        snapshot = s
        persist(s)
    }

    private func persist(_ s: Snapshot) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        cacheDefaults.set(data, forKey: Self.cacheKey)
    }

    private func loadFromCache() {
        guard snapshot == nil,
              let data = cacheDefaults.data(forKey: Self.cacheKey),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        snapshot = s
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            // The inbox holds the latest context the iPhone pushed while the
            // watch app wasn't running — read it, don't wait for a new push.
            self.ingest(session.receivedApplicationContext)
            if self.snapshot == nil {
                self.requestSnapshot()
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        DispatchQueue.main.async { self.ingest(ctx) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            if session.isReachable, self.snapshot == nil {
                self.requestSnapshot()
            }
        }
    }
}