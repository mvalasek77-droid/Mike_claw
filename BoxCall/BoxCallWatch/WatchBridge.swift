import Foundation
import WatchConnectivity
import Combine

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
    }

    @Published private(set) var snapshot: Snapshot?

    private static let appGroup = "group.com.boxcall.shared"
    private static let storageKey = "watch.snapshot.v2"

    override init() {
        super.init()
        loadFromAppGroup()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func refresh() {
        loadFromAppGroup()
    }

    private func loadFromAppGroup() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let data = defaults.data(forKey: Self.storageKey),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        snapshot = s
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { self.loadFromAppGroup() }
    }

    func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        DispatchQueue.main.async { self.loadFromAppGroup() }
    }
}
