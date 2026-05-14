import SwiftUI

/// Settings → Admin sheet. Currently exposes the workspace-archive
/// control. Keep this surface narrow — it's an admin-tier feature, not
/// something every user needs to think about.
struct AdminView: View {
    @State private var olderThanDays: Double = 30
    @State private var working: Bool = false
    @State private var lastResult: String?
    @State private var lastSummaries: [ArchiveSummary] = []
    @State private var error: String?
    private let client = SwarmClient()

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    archiveCard
                    if let lastResult { resultCard(lastResult) }
                    if !lastSummaries.isEmpty { summariesCard }
                    if let error { errorCard(error) }
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
            Text("Admin")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Maintenance + storage controls. Active jobs are always skipped.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var archiveCard: some View {
        GlassCard(title: "Archive old workspaces", icon: "archivebox.fill", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Zip job workspaces whose last activity was more than N days ago, then remove the originals from disk.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .foregroundStyle(LiquidGlass.warning)
                    Slider(value: $olderThanDays, in: 1...180, step: 1)
                        .tint(LiquidGlass.warning)
                    Text("\(Int(olderThanDays)) day\(Int(olderThanDays) == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 86, alignment: .trailing)
                }

                PrimaryButton(
                    title: working ? "Archiving…" : "Run archive",
                    systemImage: "archivebox",
                    style: .filled
                ) {
                    Task { await runArchive() }
                }
                .disabled(working)
                Text("Archives land at <workspace>/.archives/<job>-<ts>.zip on the backend.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func resultCard(_ message: String) -> some View {
        GlassCard(title: "Last run", icon: "checkmark.circle.fill", tint: LiquidGlass.success) {
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var summariesCard: some View {
        GlassCard(title: "Archived this run", icon: "list.bullet.rectangle", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(lastSummaries) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.jobID)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("\(s.filesArchived) files · \(formatBytes(s.bytesWritten))")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        GlassCard(title: "Failed", icon: "exclamationmark.triangle.fill", tint: .red) {
            Text(message)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: Action

    private func runArchive() async {
        working = true; error = nil
        defer { working = false }
        do {
            let summaries = try await client.archiveOldWorkspaces(olderThanDays: Int(olderThanDays))
            lastSummaries = summaries
            lastResult = summaries.isEmpty
                ? "Nothing to archive — every workspace is younger than \(Int(olderThanDays)) day\(Int(olderThanDays) == 1 ? "" : "s") or active."
                : "Archived \(summaries.count) workspace\(summaries.count == 1 ? "" : "s"), reclaiming \(formatBytes(summaries.reduce(0) { $0 + $1.bytesWritten })) on disk."
            Haptics.success()
        } catch {
            self.error = "\(error)"
            Haptics.error()
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb >= 1 { return String(format: "%.1fMB", mb) }
        let kb = Double(bytes) / 1024
        return String(format: "%.0fKB", kb)
    }
}
