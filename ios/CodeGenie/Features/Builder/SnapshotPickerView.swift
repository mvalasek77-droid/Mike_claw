import SwiftUI

/// Lists every snapshot (manual + orchestrator-internal) for a job
/// and lets the user pick one to restore. Restoring truncates the
/// in-memory transcript back to that checkpoint and resets any files
/// the snapshot captured.
///
/// The job must not be running when this is used — the caller is
/// responsible for calling `cancel` first if needed.
struct SnapshotPickerView: View {
    let jobID: String
    let client: SwarmClient
    /// Called with the new backend job id when the user forks a
    /// snapshot. Caller wires it into `AppSession.adoptForkedJob`.
    var onFork: ((String) -> Void)? = nil

    @State private var snapshots: [SnapshotSummary] = []
    @State private var loading = true
    @State private var error: String?
    @State private var restoreInFlight: SnapshotSummary?
    @State private var forkInFlight: SnapshotSummary?
    @State private var bannerText: String?
    @Environment(\.dismiss) private var dismiss

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
                    } else if snapshots.isEmpty {
                        emptyCard
                    } else {
                        ForEach(snapshots) { snap in
                            SnapshotRow(
                                snapshot: snap,
                                isRestoring: restoreInFlight?.id == snap.id,
                                isForking: forkInFlight?.id == snap.id,
                                onRestore: { Task { await restore(snap) } },
                                onFork: { Task { await fork(snap) } }
                            )
                        }
                    }
                    if let bannerText {
                        Text(bannerText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.success)
                            .multilineTextAlignment(.center)
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .task { await load() }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Restore a snapshot")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Pick a point in time. The workspace transcript rolls back; the orchestrator can be resumed from there.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingCard: some View {
        GlassSurface(tier: .raised) {
            HStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Loading snapshots…")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyCard: some View {
        GlassCard(title: "No snapshots yet", icon: "bookmark.slash", tint: LiquidGlass.warning) {
            Text("Tap the bookmark in the build header to save your first checkpoint, or wait for the orchestrator to land its automatic ones.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func errorCard(_ message: String) -> some View {
        GlassCard(title: "Couldn't load", icon: "exclamationmark.triangle.fill", tint: .red) {
            Text(message)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: Actions

    private func load() async {
        loading = true; error = nil
        do {
            snapshots = try await client.listSnapshots(jobID: jobID).reversed()
        } catch {
            self.error = "\(error)"
        }
        loading = false
    }

    private func restore(_ snapshot: SnapshotSummary) async {
        restoreInFlight = snapshot
        defer { restoreInFlight = nil }
        do {
            try await client.restore(jobID: jobID, label: snapshot.label)
            bannerText = "Restored to \(snapshot.label)"
            Haptics.success()
            try? await Task.sleep(nanoseconds: 600_000_000)
            dismiss()
        } catch {
            self.error = "Restore failed: \(error)"
            Haptics.error()
        }
    }

    private func fork(_ snapshot: SnapshotSummary) async {
        forkInFlight = snapshot
        defer { forkInFlight = nil }
        do {
            let newID = try await client.fork(jobID: jobID, label: snapshot.label)
            bannerText = "Forked into new job: \(newID.prefix(12))…"
            onFork?(newID)
            Haptics.success()
        } catch {
            self.error = "Fork failed: \(error)"
            Haptics.error()
        }
    }
}

private struct SnapshotRow: View {
    let snapshot: SnapshotSummary
    let isRestoring: Bool
    let isForking: Bool
    let onRestore: () -> Void
    let onFork: () -> Void

    var body: some View {
        GlassSurface(tier: .raised, corner: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: iconForLabel(snapshot.label))
                        .font(.system(size: 18))
                        .foregroundStyle(LiquidGlass.accent)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(LiquidGlass.accent.opacity(0.18)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(snapshot.files) files · \(snapshot.at, format: .relative(presentation: .named))")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Button(action: onFork) {
                        HStack(spacing: 4) {
                            if isForking { ProgressView().tint(.white).controlSize(.mini) }
                            else { Image(systemName: "arrow.triangle.branch") }
                            Text("Fork").font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.06), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
                        .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .disabled(isForking || isRestoring)
                    .accessibilityLabel("Fork into new job")

                    Spacer()
                    if isRestoring {
                        ProgressView().tint(.white)
                    } else {
                        Button("Restore", action: onRestore)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(LiquidGlass.auroraGradient.opacity(0.85), in: Capsule())
                            .disabled(isForking)
                    }
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Snapshot \(snapshot.label), \(snapshot.files) files")
    }

    private func iconForLabel(_ label: String) -> String {
        if label.hasPrefix("after-architect")       { return "rectangle.3.group" }
        if label.hasPrefix("after-build-layer")     { return "shippingbox.fill" }
        if label.hasPrefix("after-integrator")      { return "bolt.horizontal.fill" }
        if label.hasPrefix("after-tests")           { return "testtube.2" }
        if label.hasPrefix("after-custom-agents")   { return "person.crop.circle.badge.checkmark" }
        return "bookmark.fill"
    }
}
