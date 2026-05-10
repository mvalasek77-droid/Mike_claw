import SwiftUI

/// Settings sub-screen that lets the user pick a different model for
/// each swarm agent (Opus for Reviewer, Sonnet for Coder, Haiku for
/// Linter, etc.). Persists via `Credentials.setAgentModel`.
///
/// Empty selection per row = "use the swarm default" — we never silently
/// fall through to the preferred model, because picking explicitly is
/// the whole point of this screen.
struct AgentRoutingView: View {
    @StateObject private var creds = Credentials.shared
    @Environment(\.dismiss) private var dismiss

    /// Matches `AgentRole.rawValue` on the backend.
    private let agents: [Agent] = [
        .init(role: "architect",   title: "🏗️ Architect",     hint: "Plans the project shape — pays off with a flagship."),
        .init(role: "coder",       title: "💻 Coder",          hint: "Writes Swift end-to-end — balanced is the sweet spot."),
        .init(role: "designer",    title: "🎨 Designer",       hint: "SwiftUI Views — flagship for taste, balanced for speed."),
        .init(role: "integrator",  title: "🔗 Integrator",     hint: "Wires the project together — balanced or fast."),
        .init(role: "unit_tester", title: "🧪 Unit Tester",    hint: "Generates XCTests — fast is fine."),
        .init(role: "ui_tester",   title: "📱 UI Tester",      hint: "Drives simctl — fast model keeps iterations cheap."),
        .init(role: "reviewer",    title: "👁️ Code Reviewer",  hint: "Senior-engineer review — flagship recommended."),
        .init(role: "security",    title: "🔒 Security Auditor", hint: "Block-on-critical audit — flagship recommended."),
    ]

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    costEstimate
                    ForEach(agents) { agent in
                        AgentRow(
                            agent: agent,
                            currentModel: creds.agentModels[agent.role],
                            onPick: { id in creds.setAgentModel(role: agent.role, model: id) },
                            onClear: { creds.setAgentModel(role: agent.role, model: nil) }
                        )
                    }
                    resetButton
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Route per agent")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Send each agent to the model that does its job best. The swarm uses the preferred model anywhere you don't override.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var costEstimate: some View {
        let total = agents.reduce(0.0) { sum, agent in
            let id = creds.agentModels[agent.role] ?? creds.preferredModelID
            let model = ModelCatalogue.model(id: id) ?? ModelCatalogue.all[0]
            return sum + model.estimatedBuildCostUSD(inputTokens: 30_000, outputTokens: 10_000)
        }
        return GlassCard(title: "Projected cost per build", icon: "dollarsign.circle.fill", tint: LiquidGlass.success) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "$%.3f", total))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("for all 8 agents combined")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
        }
    }

    private var resetButton: some View {
        PrimaryButton(title: "Reset all to default", systemImage: "arrow.counterclockwise", style: .ghost) {
            for agent in agents { creds.setAgentModel(role: agent.role, model: nil) }
            Haptics.tap(intensity: 0.5, sharpness: 0.7)
        }
        .padding(.top, 4)
    }
}

private struct Agent: Identifiable, Hashable {
    let role: String
    let title: String
    let hint: String
    var id: String { role }
}

private struct AgentRow: View {
    let agent: Agent
    let currentModel: String?
    let onPick: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        GlassCard(title: agent.title, icon: nil, tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 10) {
                Text(agent.hint)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        DefaultChip(selected: currentModel == nil, onTap: onClear)
                        ForEach(ModelCatalogue.all) { m in
                            ModelChip(
                                model: m,
                                selected: currentModel == m.id,
                                onTap: { onPick(m.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct DefaultChip: View {
    let selected: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: { Haptics.selection(); onTap() }) {
            Text("Default")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    selected
                    ? AnyShapeStyle(Color.white.opacity(0.16))
                    : AnyShapeStyle(Color.white.opacity(0.04)),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.45 : 0.12)))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.65))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use the default model")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ModelChip: View {
    let model: AIModel
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: { Haptics.selection(); onTap() }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(String(format: "$%.0f / $%.0f", model.inputUSDPerMTok, model.outputUSDPerMTok))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                selected
                ? AnyShapeStyle(LiquidGlass.auroraGradient)
                : AnyShapeStyle(Color.white.opacity(0.06)),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(selected ? 0.45 : 0.12)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.displayName)")
        .accessibilityValue(String(format: "$%.0f input, $%.0f output", model.inputUSDPerMTok, model.outputUSDPerMTok))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
