import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Pushes the same snapshot the home widget uses over to the paired
/// Apple Watch via WatchConnectivity ApplicationContext (delivered
/// even when the watch app isn't running).
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

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
        guard let session, session.isPaired, session.isWatchAppInstalled else { return }
        let market = MarketService.shared
        let portfolio = PortfolioService.shared

        guard let next = market.movies
            .filter({ $0.daysToRelease >= 0 })
            .sorted(by: { $0.daysToRelease < $1.daysToRelease })
            .first else { return }

        let top = portfolio.positions.filter { $0.isOpen }.max { $0.cost < $1.cost }
        var payload: [String: Any] = [
            "nextMovieTitle": next.title,
            "nextMoviePoster": next.posterEmoji,
            "nextMovieOpensIn": next.daysToRelease,
            "updatedAt": Date().timeIntervalSince1970
        ]
        if let p = top, let m = market.movie(id: p.movieId) {
            let chain = market.chain(for: p.movieId)
            let mark = chain.first(where: { $0.id == p.contractId })?.premium ?? p.entryPremium
            payload["topPositionMovie"] = m.title
            payload["topPositionSideLabel"] = "\(p.side.display) $\(Int(p.strikeMillions))M"
            payload["topPositionMark"] = mark
            payload["topPositionPnL"] = (mark - p.entryPremium) * Double(p.quantity)
        }
        // The watch decodes a matching Snapshot struct.
        struct Snapshot: Codable {
            let nextMovieTitle: String
            let nextMoviePoster: String
            let nextMovieOpensIn: Int
            let topPositionMovie: String?
            let topPositionSideLabel: String?
            let topPositionMark: Double?
            let topPositionPnL: Double?
            let updatedAt: Date
        }
        let snap = Snapshot(
            nextMovieTitle: payload["nextMovieTitle"] as? String ?? "",
            nextMoviePoster: payload["nextMoviePoster"] as? String ?? "🎬",
            nextMovieOpensIn: payload["nextMovieOpensIn"] as? Int ?? 0,
            topPositionMovie: payload["topPositionMovie"] as? String,
            topPositionSideLabel: payload["topPositionSideLabel"] as? String,
            topPositionMark: payload["topPositionMark"] as? Double,
            topPositionPnL: payload["topPositionPnL"] as? Double,
            updatedAt: Date()
        )
        if let data = try? JSONEncoder().encode(snap) {
            try? session.updateApplicationContext(["snapshot": data])
        }
    }
    #else
    @MainActor func push() {}
    #endif
}

#if canImport(WatchConnectivity)
extension WatchSyncService: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#endif
