import SwiftUI

/// Shows the most recent activity for one custom agent — the
/// `agent.thought` lines captured from the SSE stream during the
/// last build that ran it. Reads from `CustomAgentLog.shared`.
struct CustomAgentLastRunView: View {
    let agent: CustomAgent
    @ObservedObject private var log = CustomAgentLog.shared
    @Environment(\.dismiss) private var dismiss

    private var run: CustomAgentLog.AgentRun? {
        let key = "🧩 \(agent.name)"
        return log.runs[key]
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if let run {
                        meta(run)
                        if run.thoughts.isEmpty {
                            emptyCard
                        } else {
                            thoughtList(run)
                        }
                        clearRow
                    } else {
                        notRunCard
                    }
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
            Text(agent.name)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Last run findings")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.accent)
                .textCase(.uppercase)
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meta(_ run: CustomAgentLog.AgentRun) -> some View {
        GlassCard(title: "Run", icon: "calendar", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 6) {
                metaRow("Started", run.startedAt.formatted(date: .numeric, time: .shortened))
                if let finished = run.finishedAt {
                    metaRow("Finished", finished.formatted(date: .numeric, time: .shortened))
                    let dur = finished.timeIntervalSince(run.startedAt)
                    metaRow("Duration", String(format: "%.1fs", dur))
                } else {
                    metaRow("Finished", "in progress")
                }
                metaRow("Thoughts", "\(run.thoughts.count)")
            }
        }
    }

    private func metaRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .frame(width: 90, alignment: .leading)
            Text(v).foregroundStyle(LiquidGlass.primaryText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Spacer()
        }
    }

    private func thoughtList(_ run: CustomAgentLog.AgentRun) -> some View {
        GlassCard(title: "Findings", icon: "bubble.left.fill", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(run.thoughts.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                            .frame(width: 18, alignment: .trailing)
                        Text(line)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var emptyCard: some View {
        GlassCard(title: "No findings recorded", icon: "tray", tint: LiquidGlass.warning) {
            Text("This agent ran but didn't emit any thoughts. The model probably ran tool calls without commentary.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
        }
    }

    private var notRunCard: some View {
        GlassCard(title: "Not run yet", icon: "hourglass", tint: LiquidGlass.warning) {
            Text("This agent hasn't joined a build yet. Findings will appear here after the next build it participates in.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
        }
    }

    private var clearRow: some View {
        Button("Clear last run") {
            log.forget(agentTitle: "🧩 \(agent.name)")
            Haptics.warning()
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(LiquidGlass.warning)
    }
}
