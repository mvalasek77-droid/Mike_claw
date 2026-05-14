import SwiftUI

/// Inline unified-diff view for a single file across two jobs.
/// Reuses the same hunk renderer logic the build-time `DiffPreviewView`
/// uses, just without the accept/reject controls.
struct CompareFileView: View {
    let entry: ProjectDiff.FileEntry
    let jobA: String
    let jobB: String
    let client: SwarmClient

    @State private var aBody: String?
    @State private var bBody: String?
    @State private var loading: Bool = true
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if loading {
                        loadingCard
                    } else if let error {
                        errorCard(error)
                    } else {
                        hunkCard
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(statusBadge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusTint.opacity(0.18), in: Capsule())
                    .overlay(Capsule().strokeBorder(statusTint.opacity(0.4)))
                    .foregroundStyle(statusTint)
                Spacer()
            }
            Text(entry.path)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingCard: some View {
        GlassSurface(tier: .raised) {
            HStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Loading both versions…")
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

    private var hunkCard: some View {
        GlassCard(title: "Unified diff", icon: "doc.text.fill", tint: LiquidGlass.accent) {
            let synthetic = FileDiff(
                path: entry.path,
                operation: .modify,
                before: aBody ?? "",
                after:  bBody ?? "",
                additions: 0,
                deletions: 0
            )
            DiffBodyView(hunks: synthetic.hunks())
        }
    }

    private var statusBadge: String {
        switch entry.status {
        case "modified": "MODIFIED"
        case "added":    "ADDED IN B"
        case "removed":  "REMOVED FROM A"
        default:         entry.status.uppercased()
        }
    }

    private var statusTint: Color {
        switch entry.status {
        case "modified": LiquidGlass.accent
        case "added":    LiquidGlass.success
        case "removed":  .red.opacity(0.85)
        default:         .white.opacity(0.5)
        }
    }

    private func load() async {
        loading = true; error = nil
        do {
            let (a, b) = try await client.compareFile(jobA: jobA, jobB: jobB, path: entry.path)
            aBody = a
            bBody = b
        } catch {
            self.error = "\(error)"
        }
        loading = false
    }
}

// MARK: - Diff body renderer (shared shape with DiffPreviewView)
//
// We deliberately keep this private to the file rather than reaching
// across module boundaries — the build-time diff and the post-build
// comparison have different audiences and may diverge.

private struct DiffBodyView: View {
    let hunks: [FileDiff.Hunk]
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(hunks) { hunk in
                HStack(spacing: 0) {
                    Text(prefix(hunk.kind))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(tint(hunk.kind))
                        .frame(width: 18, alignment: .leading)
                    Text(hunk.content.isEmpty ? " " : hunk.content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(textTint(hunk.kind))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(background(hunk.kind))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func prefix(_ k: FileDiff.Hunk.Kind) -> String {
        switch k { case .added: "+"; case .removed: "−"; case .same: " " }
    }
    private func tint(_ k: FileDiff.Hunk.Kind) -> Color {
        switch k {
        case .added:   LiquidGlass.success
        case .removed: .red.opacity(0.9)
        case .same:    .white.opacity(0.4)
        }
    }
    private func textTint(_ k: FileDiff.Hunk.Kind) -> Color {
        switch k {
        case .added:   .white
        case .removed: .white.opacity(0.85)
        case .same:    .white.opacity(0.7)
        }
    }
    private func background(_ k: FileDiff.Hunk.Kind) -> Color {
        switch k {
        case .added:   LiquidGlass.success.opacity(0.18)
        case .removed: Color.red.opacity(0.18)
        case .same:    .clear
        }
    }
}
