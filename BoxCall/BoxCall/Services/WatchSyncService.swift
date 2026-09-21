import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Builds the portfolio snapshot the watch app displays and ships it
/// over WCSession. App Group writes are kept for the iOS widget only —
/// the WATCH reads exclusively from the WCSession payload (app groups
/// do not cross devices).
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

    private static let appGroup = "group.com.boxcall.shared"
    private static let storageKey = "watch.snapshot.v2"

    #if canImport(WatchConnectivity)
    private var session: WCSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    @MainActor
    func push() {
        let snapshot = buildSnapshot()
        writeToAppGroup(snapshot)
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? session.updateApplicationContext(["snapshot": data])
        }
    }

    /// The watch app asks for a fresh snapshot when it becomes active
    /// (scenePhase) or finishes activation. WCSession delivers this on
    /// a background queue; rebuild + push on the main actor.
    private func handleWatchRequest() {
        Task { @MainActor in self.push() }
    }

    /// Marks move every few seconds, but `updateApplicationContext`
    /// coalesces to the latest state, so a slow cadence keeps the watch
    /// reasonably fresh without churning WCSession. Runs only while the
    /// iOS app is alive (timer dies with it — no background drain).
    private var pushTimer: Timer?

    func startAutoPush(interval: TimeInterval = 60) {
        guard WCSession.isSupported() else { return }
        pushTimer?.invalidate()
        pushTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.push() }
        }
    }
    #else
    @MainActor func push() {
        writeToAppGroup(buildSnapshot())
    }
    #endif

    // MARK: - Snapshot model (mirrors WatchBridge.Snapshot)
    //
    // Internal (not private) so the wire-contract test can construct and
    // encode one — the watch decodes this exact shape.

    struct PositionSnap: Codable {
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
    }

    @MainActor
    private func buildSnapshot() -> Snapshot {
        let market = MarketService.shared
        let portfolio = PortfolioService.shared

        let next = market.movies
            .filter { $0.daysToRelease >= 0 }
            .sorted { $0.daysToRelease < $1.daysToRelease }
            .first

        let positionSnaps: [PositionSnap] = portfolio.positions.map { p in
            let movie = market.movie(id: p.movieId)
            let chain = market.chain(for: p.movieId)
            let mark = chain.first { $0.id == p.contractId }?.premium ?? p.entryPremium
            let pnl = p.pnl(mark: mark)
            return PositionSnap(
                id: p.id.uuidString,
                movieTitle: movie?.title ?? "Unknown",
                movieEmoji: movie?.posterEmoji ?? "🎬",
                sideLabel: p.side.display,
                strikeMillions: p.strikeMillions,
                quantity: p.quantity,
                entryPremium: p.entryPremium,
                mark: mark,
                pnl: pnl,
                isSettled: !p.isOpen,
                settledPayout: p.settledPayout
            )
        }

        let totalPnL = positionSnaps.reduce(0.0) { $0 + $1.pnl }

        return Snapshot(
            updatedAt: Date(),
            nextMovieTitle: next?.title ?? "—",
            nextMoviePoster: next?.posterEmoji ?? "🎬",
            nextMovieOpensIn: next?.daysToRelease ?? 0,
            balance: portfolio.user.reelCoins,
            totalPnL: totalPnL,
            positions: positionSnaps
        )
    }

    private func writeToAppGroup(_ snapshot: Snapshot) {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

#if canImport(WatchConnectivity)
extension WatchSyncService: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    /// The watch pings us for a fresh snapshot (fire-and-forget).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "snapshot" {
            handleWatchRequest()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#endif