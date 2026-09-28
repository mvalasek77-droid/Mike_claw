import Foundation
import WatchConnectivity
import Combine
import WidgetKit

/// Watch-side mirror of the iPhone portfolio.
///
/// App Group containers don't span devices, so the iPhone delivers the
/// snapshot through WatchConnectivity's application context (the system
/// keeps only the latest one and delivers it when the watch can receive).
/// The watch then caches it in its own App Group so the complication and
/// the next launch have data even when the phone is out of range.
@MainActor
final class WatchBridge: NSObject, ObservableObject {
    static let shared = WatchBridge()

    // MARK: - Snapshot model (mirrors WatchSyncService on iPhone)

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

        /// The open trade moving the most, for the complication.
        var topOpenPosition: PositionSnap? {
            positions.filter { !$0.isSettled }.max { abs($0.pnl) < abs($1.pnl) }
        }
    }

    @Published private(set) var snapshot: Snapshot?

    nonisolated static let appGroup = "group.com.boxcall.shared"
    nonisolated static let storageKey = "watch.snapshot.v2"

    /// The last snapshot this watch received. Callable from the complication.
    nonisolated static func cachedSnapshot() -> Snapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    override init() {
        super.init()
        snapshot = Self.cachedSnapshot()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func refresh() {
        if WCSession.isSupported(),
           let data = WCSession.default.receivedApplicationContext["snapshot"] as? Data {
            apply(data)
        } else {
            snapshot = Self.cachedSnapshot()
        }
    }

    private func apply(_ data: Data) {
        guard let incoming = try? JSONDecoder().decode(Snapshot.self, from: data),
              incoming.updatedAt >= (snapshot?.updatedAt ?? .distantPast) else { return }
        snapshot = incoming
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        guard let data = session.receivedApplicationContext["snapshot"] as? Data else { return }
        Task { @MainActor in self.apply(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context["snapshot"] as? Data else { return }
        Task { @MainActor in self.apply(data) }
    }
}
