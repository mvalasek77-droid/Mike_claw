import SwiftUI

/// Browser for archived workspaces. Reads `/admin/archives`, lets the
/// user re-extract any zip back into the live workspace_root. Read
/// from Settings → Admin.
struct ArchivedJobsView: View {
    @State private var archives: [ArchivedJob] = []
    @State private var loading = true
    @State private var error: String?
    @State private var extractingID: String?
    @State private var banner: String?
    private let client = SwarmClient()

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if let error { errorCard(error) }
                    if loading { loadingCard }
                    else if archives.isEmpty { emptyCard }
                    else {
                        ForEach(archives) { archive in
                            ArchiveRow(
                                archive: archive,
                                isExtracting: extractingID == archive.id,
                                onExtract: { Task { await extract(archive) } }
                            )
                        }
                    }
                    if let banner {
                        Text(banner)
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
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Archived workspaces")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Job workspaces that were rotated out to a zip. Re-extract to bring one back online.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingCard: some View {
        GlassSurface(tier: .raised) {
            HStack(spacing: 12) {
                ProgressView().tint(LiquidGlass.primaryText)
                Text("Loading archives…")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyCard: some View {
        GlassCard(title: "Empty archive", icon: "archivebox", tint: LiquidGlass.success) {
            Text("Nothing rotated out yet. Use Settings → Admin → Run archive to free disk.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
        }
    }

    private func errorCard(_ message: String) -> some View {
        GlassCard(title: "Couldn't load", icon: "exclamationmark.triangle.fill", tint: .red) {
            Text(message)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
        }
    }

    private func reload() async {
        loading = true; error = nil
        do { archives = try await client.listArchives() }
        catch { self.error = "\(error)" }
        loading = false
    }

    private func extract(_ archive: ArchivedJob) async {
        extractingID = archive.id
        defer { extractingID = nil }
        do {
            let restored = try await client.extractArchive(filename: archive.filename)
            banner = "Restored \(restored.prefix(12))… — open it from the Apps tab."
            await reload()
            Haptics.success()
        } catch {
            self.error = "Extract failed: \(error)"
            Haptics.error()
        }
    }
}

private struct ArchiveRow: View {
    let archive: ArchivedJob
    let isExtracting: Bool
    let onExtract: () -> Void

    var body: some View {
        GlassSurface(tier: .raised, corner: 18) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(LiquidGlass.warning)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LiquidGlass.warning.opacity(0.18)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(archive.jobID)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(formatBytes(archive.sizeBytes)) · \(archive.mtime, format: .relative(presentation: .named))")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                }
                Spacer()
                if isExtracting {
                    ProgressView().tint(LiquidGlass.primaryText)
                } else {
                    Button("Re-extract", action: onExtract)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.10), in: Capsule())
                        .foregroundStyle(LiquidGlass.primaryText)
                }
            }
            .padding(12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Archive \(archive.jobID), \(formatBytes(archive.sizeBytes))")
    }

    private func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1024 / 1024
        return mb >= 1
            ? String(format: "%.1fMB", mb)
            : String(format: "%.0fKB", Double(bytes) / 1024)
    }
}
