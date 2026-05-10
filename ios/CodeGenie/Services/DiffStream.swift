import Foundation
import Combine

/// Subscribes to a `SwarmClient` and assembles `FileDiff`s from `diff`
/// events so the UI can present a Cursor-style review experience.
///
/// Each `diff` event is a single file. We accumulate them until the
/// orchestrator emits `agent.finished` for the Reviewer (or the user
/// taps "Review changes" manually). Decisions go back to the backend
/// via `POST /api/coding/swarm/{job}/decisions`.
@MainActor
final class DiffStream: ObservableObject {
    @Published private(set) var pending: [FileDiff] = []
    @Published private(set) var jobID: String?

    private var cancellables: Set<AnyCancellable> = []
    private weak var client: SwarmClient?

    func bind(to client: SwarmClient) {
        cancellables.removeAll()
        pending = []
        self.client = client
        self.jobID = client.jobID
        client.$events
            .sink { [weak self] events in self?.consume(events) }
            .store(in: &cancellables)
    }

    private func consume(_ events: [SwarmEvent]) {
        // Re-assemble from scratch each time. Cheap (< few hundred events)
        // and avoids drift if events arrive out of order.
        var rebuilt: [FileDiff] = []
        for event in events where event.type == "diff" {
            guard let path = event.payload["path"] as? String,
                  let opStr = event.payload["operation"] as? String,
                  let op = FileDiff.Operation(rawValue: opStr) else { continue }
            let before = event.payload["before"] as? String
            let after  = event.payload["after"]  as? String
            let additions = event.payload["additions"] as? Int ?? 0
            let deletions = event.payload["deletions"] as? Int ?? 0
            rebuilt.append(FileDiff(
                path: path, operation: op,
                before: before, after: after,
                additions: additions, deletions: deletions
            ))
        }
        pending = rebuilt
        jobID = client?.jobID
    }

    /// Send the user's accept/reject decisions back to the backend.
    func submit(decisions: [FileDiff]) async throws {
        guard let jobID, let client else { return }
        let body: [String: Any] = [
            "decisions": decisions.map {
                ["path": $0.path, "status": $0.status == .accepted ? "accept" : "reject"]
            }
        ]
        _ = try await client.postDecisions(jobID: jobID, body: body)
    }
}
