import Foundation
import Combine

/// Per-backend-job cumulative spend, persisted across launches.
/// Updated whenever a `cost.update` event lands. Surfaced by the
/// Apps tab so the user can see "$0.32 spent" on every row.
@MainActor
final class JobCostLog: ObservableObject {
    static let shared = JobCostLog()

    /// Map of backend job id → spend snapshot.
    @Published private(set) var spends: [String: Spend] = [:]

    struct Spend: Codable, Hashable {
        var jobID: String
        var usd: Double
        var inputTokens: Int
        var outputTokens: Int
        var updatedAt: Date
    }

    private static let storageKey = "job.cost.log.v1"
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: Spend].self, from: data) {
            spends = decoded
        }
    }

    /// Subscribe to a swarm client. Updates the entry for its current
    /// jobID whenever a `cost.update` event lands. The backend's
    /// authoritative spend wins over the iOS-side approximation.
    func bind(to client: SwarmClient) {
        cancellables.removeAll()
        let bound = client
        bound.$events
            .sink { [weak self] events in
                guard let self else { return }
                guard let jobID = bound.jobID else { return }
                self.ingest(events, jobID: jobID)
            }
            .store(in: &cancellables)
    }

    /// Look up the spend for a backend job id, if any.
    func spend(for jobID: String) -> Spend? { spends[jobID] }

    /// Total across all known jobs — useful for an aggregate display.
    var totalUSD: Double { spends.values.reduce(0) { $0 + $1.usd } }

    func reset() {
        spends.removeAll()
        persist()
    }

    // MARK: - Internals

    private func ingest(_ events: [SwarmEvent], jobID: String) {
        var latestUSD: Double?
        var latestIn = 0
        var latestOut = 0
        for event in events where event.type == "cost.update" {
            if let spent = event.payload["spend_usd"] as? Double { latestUSD = spent }
            if let inT = event.payload["input_tokens"] as? Int { latestIn = inT }
            if let outT = event.payload["output_tokens"] as? Int { latestOut = outT }
        }
        guard let usd = latestUSD else { return }
        let prev = spends[jobID]
        // Only persist when something actually changed — avoids
        // thrashing UserDefaults on every SSE tick.
        if prev?.usd == usd && prev?.inputTokens == latestIn && prev?.outputTokens == latestOut {
            return
        }
        spends[jobID] = Spend(
            jobID: jobID,
            usd: usd,
            inputTokens: latestIn,
            outputTokens: latestOut,
            updatedAt: .now
        )
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(spends) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
