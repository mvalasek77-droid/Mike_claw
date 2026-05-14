import SwiftUI

/// Picker that asks the user which job to compare against `originJob`.
/// Lists every other project the iOS app knows about that has a
/// backend id (otherwise there's nothing to diff against).
struct CompareJobsPickerView: View {
    let originJob: BuildJob
    let originBackendID: String
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var selected: BuildJob?

    private var candidates: [(BuildJob, String)] {
        session.recentJobs.compactMap { job in
            guard job.id != originJob.id,
                  let backend = session.backendJobIDs[job.id] else { return nil }
            return (job, backend)
        }
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if candidates.isEmpty {
                        emptyCard
                    } else {
                        ForEach(candidates, id: \.1) { pair in
                            row(for: pair.0, backendID: pair.1)
                        }
                    }
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(item: $selected) { other in
            if let otherBackend = session.backendJobIDs[other.id] {
                CompareJobsView(
                    jobA: originJob, backendA: originBackendID,
                    jobB: other,     backendB: otherBackend
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Compare \(originJob.description.title)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Pick another build to diff side-by-side. Only jobs the swarm has produced are listed.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyCard: some View {
        GlassCard(title: "Nothing to compare against", icon: "questionmark.folder", tint: LiquidGlass.warning) {
            Text("You need at least one other forked or backend-tracked build before a comparison is possible.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func row(for job: BuildJob, backendID: String) -> some View {
        Button { selected = job; Haptics.selection() } label: {
            GlassSurface(tier: .raised, corner: 18) {
                HStack(spacing: 12) {
                    Image(systemName: job.description.category.systemImage)
                        .font(.system(size: 18))
                        .foregroundStyle(LiquidGlass.accentSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(LiquidGlass.accentSecondary.opacity(0.18)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.description.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(backendID.prefix(16) + "…")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Compare against \(job.description.title)")
    }
}

// --------------------------------------------------------------------------- //

/// Renders the file-tree diff returned by `/compare/{a}/{b}` and lets
/// the user drill into a single file for the inline hunk view.
struct CompareJobsView: View {
    let jobA: BuildJob
    let backendA: String
    let jobB: BuildJob
    let backendB: String
    @Environment(\.dismiss) private var dismiss

    @State private var diff: ProjectDiff?
    @State private var loading: Bool = true
    @State private var error: String?
    @State private var openFile: ProjectDiff.FileEntry?
    private let client = SwarmClient()

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 14) {
                        summaryCard
                        if loading {
                            loadingCard
                        } else if let error {
                            errorCard(error)
                        } else if let diff {
                            fileSections(diff)
                        }
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task { await load() }
        .sheet(item: $openFile) { entry in
            CompareFileView(
                entry: entry, jobA: backendA, jobB: backendB, client: client
            )
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(10).background(.white.opacity(0.08), in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Close comparison")
            Spacer()
            Text("Compare")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private var summaryCard: some View {
        GlassCard(title: "Side by side", icon: "rectangle.split.2x1.fill", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 10) {
                jobLine(label: "A", title: jobA.description.title, backend: backendA)
                jobLine(label: "B", title: jobB.description.title, backend: backendB)
                if let counts = diff?.counts {
                    Divider().background(.white.opacity(0.12))
                    HStack(spacing: 10) {
                        countPill(label: "Modified", value: counts["modified"] ?? 0, color: LiquidGlass.accent)
                        countPill(label: "Added",    value: counts["added"]    ?? 0, color: LiquidGlass.success)
                        countPill(label: "Removed",  value: counts["removed"]  ?? 0, color: .red.opacity(0.85))
                    }
                }
            }
        }
    }

    private func jobLine(label: String, title: String, backend: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(LiquidGlass.accent.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(LiquidGlass.accent.opacity(0.35)))
                .foregroundStyle(LiquidGlass.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(backend.prefix(16) + "…")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
    }

    private func countPill(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private var loadingCard: some View {
        GlassSurface(tier: .raised) {
            HStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Diffing workspaces…")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(20).frame(maxWidth: .infinity)
        }
    }

    private func errorCard(_ message: String) -> some View {
        GlassCard(title: "Couldn't load", icon: "exclamationmark.triangle.fill", tint: .red) {
            Text(message)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func fileSections(_ diff: ProjectDiff) -> some View {
        VStack(spacing: 12) {
            if diff.files.isEmpty {
                GlassCard(title: "Identical", icon: "checkmark.seal.fill", tint: LiquidGlass.success) {
                    Text("Every file in both workspaces matches. Nothing to diff.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            ForEach(diff.grouped, id: \.status) { group in
                GlassCard(title: title(for: group.status), icon: icon(for: group.status), tint: tint(for: group.status)) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(group.files) { entry in
                            fileRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func fileRow(_ entry: ProjectDiff.FileEntry) -> some View {
        Button {
            guard entry.isTextLike else { Haptics.warning(); return }
            openFile = entry
            Haptics.selection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.isTextLike ? "doc.text" : "doc")
                    .foregroundStyle(.white.opacity(entry.isTextLike ? 0.8 : 0.35))
                    .accessibilityHidden(true)
                Text(entry.path)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let bytes = entry.bSize ?? entry.aSize {
                    Text(formatBytes(bytes))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(entry.isTextLike ? 0.55 : 0.2))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entry.isTextLike)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.status) \(entry.path)")
        .accessibilityHint(entry.isTextLike ? "Open inline diff" : "Binary file; not opening inline")
    }

    private func title(for status: String) -> String {
        switch status {
        case "modified": "Modified"
        case "added":    "Added in B"
        case "removed":  "Removed from A"
        case "same":     "Unchanged"
        default:         status.capitalized
        }
    }

    private func icon(for status: String) -> String {
        switch status {
        case "modified": "pencil.line"
        case "added":    "plus.circle.fill"
        case "removed":  "minus.circle.fill"
        case "same":     "equal.circle.fill"
        default:         "doc"
        }
    }

    private func tint(for status: String) -> Color {
        switch status {
        case "modified": LiquidGlass.accent
        case "added":    LiquidGlass.success
        case "removed":  .red.opacity(0.85)
        case "same":     .white.opacity(0.5)
        default:         LiquidGlass.accent
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1fKB", kb) }
        return String(format: "%.1fMB", kb / 1024)
    }

    private func load() async {
        loading = true; error = nil
        do {
            diff = try await client.compareJobs(jobA: backendA, jobB: backendB)
        } catch {
            self.error = "\(error)"
        }
        loading = false
    }
}
