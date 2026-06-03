import SwiftUI

/// Operator-facing money-flow ledger viewer. Pulls recent entries from the
/// Worker's KV-backed `/ledger` route — previously the ledger was curl-only.
/// Admin can filter by scope (the "platform" string for treasury events, or
/// a `acct_xxx` Stripe Connect id for a specific creator). Read-only.
struct AdminLedgerView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var scope: String = "platform"
    @State private var entries: [[String: Any]] = []
    @State private var loading = false
    @State private var lastError: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    scopeField
                    if loading {
                        ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if entries.isEmpty {
                        emptyCard
                    } else {
                        ForEach(entries.indices, id: \.self) { row(entries[$0]) }
                    }
                    if let err = lastError {
                        Text(err).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.warning)
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.accent).ignoresSafeArea())
            .navigationTitle("Ledger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .cancellationAction) {
                    Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(loading)
                }
            }
        }
        .task { await refresh() }
    }

    private var scopeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scope").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            HStack(spacing: 8) {
                TextField("platform or acct_xxx", text: $scope, onCommit: { Task { await refresh() } })
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
                Button("Load") { Task { await refresh() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.accent))
            }
            Text("Tip: \"platform\" for treasury / top-ups / disputes, or a creator's acct_… id.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
        }
    }

    private func row(_ e: [String: Any]) -> some View {
        let type = (e["type"] as? String) ?? "?"
        let status = (e["status"] as? String) ?? "?"
        let cents = (e["amountCents"] as? Int) ?? 0
        let currency = (e["currency"] as? String) ?? ""
        let ts = (e["ts"] as? String) ?? ""
        let note = (e["note"] as? String) ?? ""
        let stripeId = (e["stripeId"] as? String) ?? ""
        let tint = colorForStatus(status)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(type.uppercased()) · \(status)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                Spacer()
                Text(formatAmount(cents: cents, currency: currency))
                    .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
            }
            Text(ts.prefix(19))
                .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.inkFaint)
            if !note.isEmpty {
                Text(note).font(.system(size: 12, weight: .regular)).foregroundStyle(Theme.inkSoft).lineLimit(3)
            }
            if !stripeId.isEmpty {
                Text("stripe: \(stripeId)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint).lineLimit(1)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.25), lineWidth: 0.6))
    }

    private var emptyCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray").font(.system(size: 28)).foregroundStyle(Theme.inkSoft)
            Text("No ledger entries for \"\(scope)\".")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("Check the scope — most operator events live under \"platform\"; per-creator transfers/payouts live under their acct_… id.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func refresh() async {
        loading = true
        lastError = nil
        let trimmed = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { loading = false; return }
        let result = await store.fetchLedgerEntries(scope: trimmed)
        entries = result
        loading = false
        if result.isEmpty, !store.payoutBaseURL.isEmpty {
            // No error, just nothing under that scope.
        }
    }

    private func formatAmount(cents: Int, currency: String) -> String {
        let dollars = Double(cents) / 100
        return String(format: "%.2f %@", dollars, currency.uppercased())
    }

    private func colorForStatus(_ s: String) -> Color {
        switch s {
        case "succeeded", "won": return Theme.success
        case "failed", "reversed", "funds_withdrawn", "lost": return Theme.warning
        case "pending": return Theme.accent
        default: return Theme.inkSoft
        }
    }
}
