import Foundation
import Combine

/// Persists the most recent run of each custom agent so the user can
/// review findings later from Settings → Custom agents.
///
/// We subscribe to a `SwarmClient`'s events and capture every
/// `agent.thought` whose agent title starts with the `🧩` marker the
/// orchestrator uses for custom-agent blueprints. New runs replace
/// older ones — this is "last run", not history.
@MainActor
final class CustomAgentLog: ObservableObject {
    static let shared = CustomAgentLog()

    @Published private(set) var runs: [String: AgentRun] = [:]

    struct AgentRun: Codable, Hashable {
        var agentTitle: String              // "🧩 Accessibility Auditor"
        var startedAt: Date
        var finishedAt: Date?
        var thoughts: [String]              // agent.thought texts, in order
        var jobID: String?
    }

    private static let storageKey = "custom.agent.log.v1"
    private var cancellables: Set<AnyCancellable> = []
    private var currentJobID: String?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: AgentRun].self, from: data) {
            runs = decoded
        }
    }

    /// Start observing a fresh build. Existing runs are kept; new
    /// custom-agent activity replaces same-titled entries.
    func bind(to client: SwarmClient) {
        cancellables.removeAll()
        currentJobID = client.jobID
        client.$events
            .sink { [weak self] events in self?.ingest(events) }
            .store(in: &cancellables)
    }

    /// Clear an entry (e.g. user removed the agent).
    func forget(agentTitle: String) {
        runs.removeValue(forKey: agentTitle)
        persist()
    }

    /// Drop everything — used by the Settings Reset action.
    func reset() {
        runs.removeAll()
        persist()
    }

    // MARK: - Internals

    private func ingest(_ events: [SwarmEvent]) {
        var updates: [String: AgentRun] = runs
        for event in events {
            guard let agent = event.agent, agent.hasPrefix("🧩") else { continue }
            switch event.type {
            case "agent.started":
                updates[agent] = AgentRun(
                    agentTitle: agent,
                    startedAt: Date(timeIntervalSince1970: event.ts),
                    finishedAt: nil,
                    thoughts: [],
                    jobID: currentJobID
                )
            case "agent.thought":
                guard let text = event.payload["text"] as? String, !text.isEmpty else { continue }
                if updates[agent] == nil {
                    updates[agent] = AgentRun(
                        agentTitle: agent,
                        startedAt: Date(timeIntervalSince1970: event.ts),
                        finishedAt: nil, thoughts: [], jobID: currentJobID
                    )
                }
                updates[agent]?.thoughts.append(text)
            case "agent.finished":
                updates[agent]?.finishedAt = Date(timeIntervalSince1970: event.ts)
            default:
                continue
            }
        }
        if updates != runs {
            runs = updates
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(runs) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
