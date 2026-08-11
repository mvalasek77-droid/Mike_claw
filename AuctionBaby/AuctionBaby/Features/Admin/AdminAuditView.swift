import SwiftUI

/// Founder-facing audit trail (Batch Q). Every mutating /admin/* call
/// writes one row: who did it, what action, on whom, when. Reads through
/// BackendService.fetchAdminAudit — session-token gated (Batch L), so the
/// operator must be signed in as an admin account.
struct AdminAuditView: View {
    @EnvironmentObject private var backend: BackendService

    @State private var entries: [BackendService.AdminAuditEntry] = []
    @State private var loading = false
    @State private var lastError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 10) {
                if loading && entries.isEmpty {
                    ProgressView().tint(Theme.gold)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else if entries.isEmpty {
                    empty
                } else {
                    ForEach(entries) { row($0) }
                }
                if let err = lastError {
                    Text(err).font(.scaled(12, weight: .semibold, relativeTo: .caption1))
                        .foregroundStyle(Theme.danger)
                }
                Spacer(minLength: 24)
            }
            .screenPadding().padding(.top, 6)
        }
        .background(AppBackground())
        .navigationTitle("Audit trail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .foregroundStyle(Theme.gold).disabled(loading)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .font(.scaled(28, relativeTo: .title1))
                .foregroundStyle(Theme.inkSoft)
            Text("No admin actions yet.")
                .font(.scaled(13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
            Text("Verify, unverify, delete, and resolve-report actions log here.")
                .font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func row(_ e: BackendService.AdminAuditEntry) -> some View {
        GlassSurface(corner: Theme.cornerM) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Chip(text: e.action, color: color(for: e.action))
                    Spacer()
                    Text(dateString(e.createdAt))
                        .font(.scaled(10, weight: .medium, design: .monospaced, relativeTo: .caption2))
                        .foregroundStyle(Theme.inkFaint)
                }
                HStack(spacing: 12) {
                    label("Actor", e.actorId.prefix(8) + "…")
                    if let t = e.targetId {
                        label("Target", t.prefix(8) + "…")
                    }
                }
                if let n = e.note, !n.isEmpty {
                    Text(n).font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkSoft)
                }
            }
            .padding(12)
        }
    }

    private func label(_ k: String, _ v: Substring.SubSequence) -> some View {
        HStack(spacing: 4) {
            Text(k.uppercased())
                .font(.scaled(9, weight: .heavy, design: .rounded, relativeTo: .caption2)).tracking(1)
                .foregroundStyle(Theme.inkFaint)
            Text(String(v))
                .font(.scaled(10, weight: .medium, design: .monospaced, relativeTo: .caption2))
                .foregroundStyle(Theme.ink)
        }
    }

    private func color(for action: String) -> Color {
        if action.hasPrefix("delete_") { return Theme.danger }
        if action.hasPrefix("unverify") { return Theme.warning }
        if action.hasPrefix("verify") { return Theme.verify }
        if action.hasPrefix("resolve_report:actioned") { return Theme.danger }
        if action.hasPrefix("resolve_report:") { return Theme.success }
        return Theme.inkFaint
    }

    private func dateString(_ ms: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    private func refresh() async {
        loading = true
        lastError = nil
        defer { loading = false }
        switch await backend.fetchAdminAudit() {
        case .success(let list): entries = list
        case .failure(let message): lastError = message
        }
    }
}
