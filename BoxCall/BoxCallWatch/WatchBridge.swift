import Foundation
import WatchConnectivity
import Combine

/// Receives snapshot updates from the iPhone via WatchConnectivity.
/// The iPhone posts the same WidgetSnapshot payload; the watch just
/// displays a subset. Persists the last-known snapshot in
/// UserDefaults so the watch has something to show before the phone
/// wakes up.
final class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchBridge()

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

    @Published private(set) var snapshot: Snapshot?
    private let storageKey = "watch.snapshot"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = s
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) { /* no-op */ }

    func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        guard let data = ctx["snapshot"] as? Data,
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        DispatchQueue.main.async {
            self.snapshot = s
            UserDefaults.standard.set(data, forKey: self.storageKey)
        }
    }
}
