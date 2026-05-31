import SwiftUI

/// One money-flow event as recorded by the Worker's independent ledger.
/// Mirrors the backend `LedgerEntry` shape (backend/src/index.ts).
struct LedgerEntry: Identifiable, Codable, Hashable {
    var ts: String
    var type: String       // sale | transfer | payout | topup | nsf
    var status: String     // succeeded | failed | pending
    var amountCents: Int
    var currency: String
    var scope: String
    var refId: String?
    var stripeId: String?
    var note: String?

    var id: String { (stripeId ?? "") + ts + (refId ?? "") }
    var amount: Double { Double(amountCents) / 100 }

    var date: Date {
        ISO8601DateFormatter().date(from: ts) ?? .distantPast
    }
}

/// Real-time view of a creator's sales and their payout status, read straight
/// from the Worker's ledger (the independent money record). Shows each
/// transfer/payout with its status, plus any NSF events flagged in red so the
/// creator knows a payout is delayed (not lost) while the operator tops up.
struct SalesActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MarketplaceStore

    @State private var entries: [LedgerEntry] = []
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        summaryRow
                        if let err = loadError { errorCard(err) }
                        if entries.isEmpty && !loading {
                            emptyState
                        } else {
                            ForEach(entries) { entry in row(entry) }
                        }
                    }
                    .screenPadding()
                    .padding(.top, 8)
                }
                .refreshable { await load() }
            }
            .navigationTitle("Sales & Payouts")
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

    private var summaryRow: some View {
        HStack(spacing: 12) {
            stat("Available", store.pendingPayoutUSD, Theme.success)
            stat("Lifetime", store.creatorEarnings, Theme.ink)
            stat("Paid out", store.paidOutUSD, Theme.inkSoft)
        }
    }

    private func stat(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(String(format: "$%.2f", value))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private func row(_ e: LedgerEntry) -> some View {
        let isNSF = e.type == "nsf" || e.status == "failed"
        return HStack(spacing: 12) {
            Image(systemName: icon(for: e))
                .font(.system(size: 16))
                .foregroundStyle(color(for: e))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: e))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(subtitle(for: e))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isNSF ? Theme.warning : Theme.inkFaint)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%@%.2f", e.currency.uppercased() == "USD" ? "$" : "", e.amount))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(color(for: e))
                Text(e.status.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(color(for: e))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(isNSF ? Theme.warning.opacity(0.10) : Color.white.opacity(0.04)))
    }

    private func icon(for e: LedgerEntry) -> String {
        switch e.type {
        case "transfer": return e.status == "failed" ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.left.arrow.right.circle.fill"
        case "payout":   return e.status == "failed" ? "xmark.circle.fill" : "banknote.fill"
        case "topup":    return "arrow.down.circle.fill"
        case "nsf":      return "exclamationmark.triangle.fill"
        default:          return "circle.fill"
        }
    }

    private func color(for e: LedgerEntry) -> Color {
        if e.type == "nsf" || e.status == "failed" { return Theme.warning }
        if e.status == "pending" { return Theme.accent }
        return Theme.success
    }

    private func title(for e: LedgerEntry) -> String {
        switch e.type {
        case "transfer": return "Sale → your Stripe balance"
        case "payout":   return "Payout to your bank"
        case "topup":    return "Platform float top-up"
        case "nsf":      return "Insufficient funds — payout delayed"
        default:          return e.type.capitalized
        }
    }

    private func subtitle(for e: LedgerEntry) -> String {
        let when = e.date == .distantPast ? "" : relative(e.date)
        if e.type == "nsf" || e.status == "failed" {
            return "Delayed, not lost — will retry once the balance is funded. \(when)"
        }
        return [when, e.note].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: .now)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36)).foregroundStyle(Theme.inkFaint)
            Text("No sales activity yet")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("When your titles sell, each transfer and payout appears here in real time, straight from the payout ledger.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
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
        let fetched = await store.fetchLedger()
        switch fetched {
        case .success(let list): entries = list
        case .failure(let msg):  loadError = msg
        }
    }
}
