import Foundation
import Combine

/// Tracks token usage as it streams in from the swarm and converts it
/// into running USD spend using the prices in `ModelCatalogue`.
///
/// Subscribes to a `SwarmClient` and updates whenever an
/// `agent.finished` event lands (the runtime emits `input_tokens` /
/// `output_tokens` in that event's payload).
@MainActor
final class CostTracker: ObservableObject {
    @Published private(set) var inputTokens: Int = 0
    @Published private(set) var outputTokens: Int = 0
    @Published private(set) var perAgent: [String: AgentCost] = [:]
    @Published private(set) var retryAttempts: Int = 0
    @Published private(set) var maxRetries: Int = 0
    /// Authoritative running spend reported by the backend (USD). 0
    /// until the first `cost.update` event lands.
    @Published private(set) var backendSpendUSD: Double = 0
    /// The cap the backend is enforcing for the current run, if any.
    @Published private(set) var backendCapUSD: Double?
    /// True when the backend has emitted `cost.cap_hit`. The UI uses
    /// this to swap the cost badge to a warning state.
    @Published private(set) var capHit: Bool = false
    /// Last `workspace.full` event the backend emitted, if any. The
    /// BuildScreen banner reads from this — UI lets the user lift the
    /// snapshot cap in Settings → Build cost cap.
    @Published private(set) var workspaceFull: WorkspaceFullState?

    struct WorkspaceFullState: Equatable {
        let label: String
        let sizeBytes: Int64
        let capBytes: Int64
    }

    struct AgentCost: Identifiable, Hashable {
        var id: String { agent }
        let agent: String
        var inputTokens: Int
        var outputTokens: Int
        var usd: Double
    }

    private let modelID: String
    private var cancellables: Set<AnyCancellable> = []
    private var lastConsumedCount: Int = 0

    init(modelID: String = ModelCatalogue.recommendedDefault) {
        self.modelID = modelID
    }

    /// Subscribe to a swarm client. Safe to call multiple times — we
    /// reset state and re-bind so the badge stays consistent across
    /// successive builds.
    func bind(to client: SwarmClient) {
        cancellables.removeAll()
        inputTokens = 0; outputTokens = 0; perAgent = [:]
        retryAttempts = 0; maxRetries = 0
        backendSpendUSD = 0; backendCapUSD = nil; capHit = false
        workspaceFull = nil
        lastConsumedCount = 0
        client.$events
            .sink { [weak self] events in self?.consumeIncremental(events) }
            .store(in: &cancellables)
    }

    /// Total USD spend for the run so far.
    var totalUSD: Double {
        let m = ModelCatalogue.model(id: modelID) ?? ModelCatalogue.all[0]
        let mtok = 1_000_000.0
        return (Double(inputTokens)  / mtok) * m.inputUSDPerMTok
             + (Double(outputTokens) / mtok) * m.outputUSDPerMTok
    }

    /// Format spend the way Settings does — three-decimal USD.
    var totalLabel: String { String(format: "$%.3f", totalUSD) }

    // MARK: - Internals

    private func consumeIncremental(_ events: [SwarmEvent]) {
        guard events.count > lastConsumedCount else { return }
        let newSlice = events[lastConsumedCount...]
        lastConsumedCount = events.count

        for event in newSlice {
            switch event.type {
            case "agent.finished":
                let inT = event.payload["input_tokens"] as? Int ?? 0
                let outT = event.payload["output_tokens"] as? Int ?? 0
                inputTokens += inT
                outputTokens += outT
                if let agent = event.agent {
                    var entry = perAgent[agent] ?? AgentCost(agent: agent, inputTokens: 0, outputTokens: 0, usd: 0)
                    entry = AgentCost(
                        agent: agent,
                        inputTokens: entry.inputTokens + inT,
                        outputTokens: entry.outputTokens + outT,
                        usd: usd(input: entry.inputTokens + inT, output: entry.outputTokens + outT)
                    )
                    perAgent[agent] = entry
                }
            case "retry.attempt":
                let n = event.payload["attempt"] as? Int ?? 0
                retryAttempts = max(retryAttempts, n)
                if let cap = event.payload["max_retries"] as? Int { maxRetries = cap }
            case "cost.update":
                if let spent = event.payload["spend_usd"] as? Double { backendSpendUSD = spent }
                if let cap = event.payload["cap_usd"] as? Double { backendCapUSD = cap }
            case "cost.cap_hit":
                capHit = true
                if let spent = event.payload["spent_usd"] as? Double { backendSpendUSD = spent }
                if let cap = event.payload["cap_usd"] as? Double { backendCapUSD = cap }
            case "workspace.full":
                let label = (event.payload["label"] as? String) ?? "(unknown)"
                let size = (event.payload["size_bytes"] as? Int).map(Int64.init)
                    ?? (event.payload["size_bytes"] as? Int64) ?? 0
                let cap = (event.payload["cap_bytes"] as? Int).map(Int64.init)
                    ?? (event.payload["cap_bytes"] as? Int64) ?? 0
                workspaceFull = WorkspaceFullState(label: label, sizeBytes: size, capBytes: cap)
            default: break
            }
        }
    }

    private func usd(input: Int, output: Int) -> Double {
        let m = ModelCatalogue.model(id: modelID) ?? ModelCatalogue.all[0]
        let mtok = 1_000_000.0
        return (Double(input)/mtok)*m.inputUSDPerMTok + (Double(output)/mtok)*m.outputUSDPerMTok
    }
}
