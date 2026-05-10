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

    struct AgentCost: Identifiable, Hashable {
        var id: String { agent }
        let agent: String
        var inputTokens: Int
        var outputTokens: Int
        var usd: Double
    }

    private let modelID: String
    private var cancellables: Set<AnyCancellable> = []

    init(modelID: String = ModelCatalogue.recommendedDefault) {
        self.modelID = modelID
    }

    /// Subscribe to a swarm client. Safe to call multiple times — we
    /// reset state and re-bind so the badge stays consistent across
    /// successive builds.
    func bind(to client: SwarmClient) {
        cancellables.removeAll()
        inputTokens = 0; outputTokens = 0; perAgent = [:]
        client.$events
            .sink { [weak self] events in self?.consume(events) }
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

    private func consume(_ events: [SwarmEvent]) {
        // Recompute from scratch so re-binds don't double-count.
        var input = 0
        var output = 0
        var byAgent: [String: AgentCost] = [:]
        for event in events where event.type == "agent.finished" {
            let inT = event.payload["input_tokens"] as? Int ?? 0
            let outT = event.payload["output_tokens"] as? Int ?? 0
            input += inT
            output += outT
            if let agent = event.agent {
                let prior = byAgent[agent]?.inputTokens ?? 0
                let priorOut = byAgent[agent]?.outputTokens ?? 0
                byAgent[agent] = AgentCost(
                    agent: agent,
                    inputTokens: prior + inT,
                    outputTokens: priorOut + outT,
                    usd: usd(input: prior + inT, output: priorOut + outT)
                )
            }
        }
        inputTokens = input
        outputTokens = output
        perAgent = byAgent
    }

    private func usd(input: Int, output: Int) -> Double {
        let m = ModelCatalogue.model(id: modelID) ?? ModelCatalogue.all[0]
        let mtok = 1_000_000.0
        return (Double(input)/mtok)*m.inputUSDPerMTok + (Double(output)/mtok)*m.outputUSDPerMTok
    }
}
