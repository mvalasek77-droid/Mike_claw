import SwiftUI

/// Operator-only screen listing creators owed an unpaid transfer (a transfer
/// that failed — usually an NSF when the platform float was short). Each row
/// has a "Pay now" button that manually re-attempts the transfer once the
/// operator has funded the float. Reached from the Admin console.
struct AdminPayoutsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MarketplaceStore

    @State private var entries: [MarketplaceStore.UnfundedEntry] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var paying: Set<String> = []      // entry ids in flight
    @State private var rowError: [String: String] = [:]

    private var totalOwed: Double { entries.reduce(0) { $0 + $1.amountUSD } }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(glow: Theme.warning).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if let err = loadError { errorCard(err) }
                        if entries.isEmpty && !loading {
                            emptyState
                        } else {
                            ForEach(entries) { row($0) }
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
                .refreshable { await load() }
            }
            .navigationTitle("Owed creators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if loading { ProgressView() }
                    else { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } }
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        GlassCard(tint: entries.isEmpty ? Theme.success : Theme.warning) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entries.isEmpty ? "All creators paid" : "\(entries.count) creator(s) owed")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if !entries.isEmpty {
                        Text(String(format: "$%.2f total", totalOwed))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.warning)
                    }
                }
                Text("These transfers failed (usually because the platform float was short). Fund the float — Stripe Dashboard → Balance → Add to balance — then tap Pay now on each. The amounts were never lost.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func row(_ e: MarketplaceStore.UnfundedEntry) -> some View {
        let inFlight = paying.contains(e.id)
        let cur = e.currency.uppercased()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.title?.isEmpty == false ? e.title! : "Sale")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text(e.accountId)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.inkFaint)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(cur == "USD" ? "$" : "")\(String(format: "%.2f", e.amountUSD))")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.warning)
            }
            Text(e.reason)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(2)
            if let err = rowError[e.id] {
                Text(err)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.warning)
            }
            Button {
                Task { await pay(e) }
            } label: {
                HStack(spacing: 6) {
                    if inFlight { ProgressView().tint(.black) }
                    Image(systemName: "banknote.fill").font(.system(size: 12))
                    Text(inFlight ? "Paying…" : "Pay now").fontWeight(.bold)
                }
                .font(.system(size: 13))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.success))
            }
            .buttonStyle(.plain)
            .disabled(inFlight)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36)).foregroundStyle(Theme.success)
            Text("No creators owed")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("If a transfer ever fails (e.g. an NSF when the float is short), the owed creator shows up here for one-tap manual payment.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(message).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.10)))
    }

    @MainActor
    private func load() async {
        loading = true; loadError = nil
        defer { loading = false }
        switch await store.fetchUnfunded() {
        case .success(let list): entries = list
        case .failure(let msg):  loadError = msg
        }
    }

    @MainActor
    private func pay(_ e: MarketplaceStore.UnfundedEntry) async {
        paying.insert(e.id); rowError[e.id] = nil
        defer { paying.remove(e.id) }
        if let err = await store.manualFund(e) {
            rowError[e.id] = err
            Haptics.warning()
        } else {
            entries.removeAll { $0.id == e.id }   // cleared server-side too
            Haptics.success()
        }
    }
}
