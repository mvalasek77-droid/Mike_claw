import SwiftUI

/// Shows failed builds the swarm has recorded in Memory, so the user
/// can review what went wrong without digging through the transcript.
/// Tapping a row reveals the reasoning decisions logged during that
/// run (the swarm's "thinking out loud" trail).
struct CrashLogView: View {
    @State private var projects: [ProjectRecord] = []
    @State private var loading = true
    @State private var error: String?
    @State private var expanded: String?
    @State private var decisionsByJob: [String: [DecisionRecord]] = [:]
    @State private var loadingDecisions: Set<String> = []
    private let client = SwarmClient()

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if let error {
                        errorCard(error)
                    } else if loading {
                        loadingCard
                    } else if projects.isEmpty {
                        emptyCard
                    } else {
                        ForEach(projects) { p in
                            FailureCard(
                                project: p,
                                isExpanded: expanded == p.jobID,
                                isLoadingDecisions: loadingDecisions.contains(p.jobID),
                                decisions: decisionsByJob[p.jobID] ?? [],
                                onToggle: { Task { await toggle(p) } }
                            )
                        }
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent build failures")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Builds the swarm marked failed. Tap a row to see what it was reasoning about when it broke.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingCard: some View {
        GlassSurface(tier: .raised) {
            HStack(spacing: 12) {
                ProgressView().tint(LiquidGlass.primaryText)
                Text("Loading…")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyCard: some View {
        GlassCard(title: "Clean record", icon: "checkmark.seal.fill", tint: LiquidGlass.success) {
            Text("No failed builds yet — every run has finished green or been cancelled.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
        }
    }

    private func errorCard(_ message: String) -> some View {
        GlassCard(title: "Couldn't load", icon: "exclamationmark.triangle.fill", tint: .red) {
            Text(message)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
        }
    }

    private func reload() async {
        loading = true; error = nil
        do {
            projects = try await client.recentProjects(limit: 30, onlyFailed: true)
        } catch {
            self.error = "\(error)"
        }
        loading = false
    }

    private func toggle(_ project: ProjectRecord) async {
        if expanded == project.jobID {
            expanded = nil
            return
        }
        expanded = project.jobID
        if decisionsByJob[project.jobID] != nil { return }
        loadingDecisions.insert(project.jobID)
        defer { loadingDecisions.remove(project.jobID) }
        do {
            decisionsByJob[project.jobID] = try await client.decisions(jobID: project.jobID)
        } catch {
            // Treat as "no decisions" rather than surfacing yet
            // another error inside the expanded row — the parent
            // error card already covers transport failures.
            decisionsByJob[project.jobID] = []
        }
    }
}

private struct FailureCard: View {
    let project: ProjectRecord
    let isExpanded: Bool
    let isLoadingDecisions: Bool
    let decisions: [DecisionRecord]
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            GlassSurface(tier: isExpanded ? .deep : .raised, corner: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundStyle(.red.opacity(0.85))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            Text(project.at, format: .relative(presentation: .named))
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    }
                    if !project.summary.isEmpty {
                        Text(project.summary)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                            .lineLimit(isExpanded ? nil : 2)
                    }
                    if isExpanded {
                        Divider().background(.white.opacity(0.1))
                        if isLoadingDecisions {
                            HStack {
                                ProgressView().tint(LiquidGlass.primaryText)
                                Text("Loading decisions…")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                            }
                        } else if decisions.isEmpty {
                            Text("No reasoning decisions were logged for this run.")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                        } else {
                            ForEach(decisions) { decision in
                                decisionRow(decision)
                            }
                        }
                    }
                }
                .padding(14)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Failed build: \(project.title)")
    }

    private func decisionRow(_ decision: DecisionRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(decision.context)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.accent)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(decision.decision)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
