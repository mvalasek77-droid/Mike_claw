import SwiftUI

/// Read-only viewer for the Worker's KV-backed money ledger. Filter by scope:
/// "platform" for treasury events (top-ups, disputes, Apple notifications) or
/// an acct_… Stripe Connect id for one woman's transfers and payouts.
struct AdminLedgerView: View {
    @EnvironmentObject private var backend: BackendService

    @State private var scope = "platform"
    @State private var entries: [BackendService.LedgerEntry] = []
    @State private var loading = false
    @State private var lastError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                scopeField
                if loading {
                    ProgressView().tint(Theme.gold)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else if entries.isEmpty {
                    emptyCard
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
        .navigationTitle("Money ledger")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .foregroundStyle(Theme.gold)
                .disabled(loading)
            }
        }
        .task { await refresh() }
    }

    private var scopeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scope").font(.scaled(12, weight: .semibold, relativeTo: .caption1)).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 8) {
                TextField("platform or acct_xxx", text: $scope)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await refresh() } }
                    .font(.scaled(13, weight: .medium, design: .monospaced, relativeTo: .footnote))
                    .foregroundStyle(Theme.ink)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
                Button("Load") { Task { await refresh() } }
                    .buttonStyle(.plain)
                    .font(.scaled(13, weight: .heavy, design: .rounded, relativeTo: .footnote))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.gold))
            }
            Text("Tip: \"platform\" for treasury / top-ups / disputes / Apple refund notifications, or a woman's acct_… id for her transfers and payouts.")
                .font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint)
        }
    }

    private func row(_ e: BackendService.LedgerEntry) -> some View {
        let tint = colorForStatus(e.status)
        return GlassSurface(corner: Theme.cornerL) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(e.type.uppercased()) · \(e.status)")
                        .font(.scaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
                        .foregroundStyle(tint)
                    Spacer()
                    Text(e.amountLabel)
                        .font(.scaled(14, weight: .heavy, design: .rounded, relativeTo: .footnote))
                        .foregroundStyle(Theme.ink)
                }
                Text(e.ts.prefix(19))
                    .font(.scaled(11, weight: .medium, design: .monospaced, relativeTo: .caption2))
                    .foregroundStyle(Theme.inkFaint)
                if let note = e.note, !note.isEmpty {
                    Text(note).font(.scaled(12, relativeTo: .caption1)).foregroundStyle(Theme.inkSoft).lineLimit(3)
                }
                if let stripeId = e.stripeId, !stripeId.isEmpty {
                    Text("stripe: \(stripeId)")
                        .font(.scaled(10, weight: .medium, design: .monospaced, relativeTo: .caption2))
                        .foregroundStyle(Theme.inkFaint).lineLimit(1)
                }
            }
            .padding(12)
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray").font(.scaled(28, relativeTo: .title1)).foregroundStyle(Theme.inkSoft)
            Text("No ledger entries for \"\(scope)\".")
                .font(.scaled(13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
            Text("Most operator events live under \"platform\"; per-woman transfers and payouts live under her acct_… id.")
                .font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func refresh() async {
        let trimmed = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        loading = true
        lastError = nil
        defer { loading = false }
        switch await backend.fetchLedger(scope: trimmed) {
        case .success(let list): entries = list
        case .failure(let message): lastError = message
        }
    }

    private func colorForStatus(_ s: String) -> Color {
        switch s {
        case "succeeded", "won": return Theme.success
        case "failed", "reversed", "funds_withdrawn", "lost": return Theme.danger
        case "pending": return Theme.warning
        default: return Theme.inkSoft
        }
    }
}
