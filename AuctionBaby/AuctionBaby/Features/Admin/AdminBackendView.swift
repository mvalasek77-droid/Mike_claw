import SwiftUI

/// Founder-only money console. Talks to the payout Worker (see `backend/`):
/// float funding, manual top-up / digest, owed-women recovery, and doorways
/// into the ledger and moderation queue. Reached from the Admin console.
struct AdminBackendView: View {
    @EnvironmentObject private var backend: BackendService
    @Environment(\.dismiss) private var dismiss

    @State private var funding: BackendService.Funding?
    @State private var unfunded: [BackendService.UnfundedEntry] = []
    @State private var loading = false
    @State private var statusLine: String?
    @State private var statusIsError = false
    @State private var paying: Set<String> = []
    @State private var secretVisible = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    configCard
                    if backend.isConfigured {
                        fundingCard
                        owedSection
                        toolsCard
                    }
                    if let line = statusLine {
                        Text(line)
                            .font(.scaled(12, weight: .semibold, relativeTo: .caption1))
                            .foregroundStyle(statusIsError ? Theme.danger : Theme.success)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("Money & backend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.gold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if loading { ProgressView().tint(Theme.gold) }
                    else {
                        Button { Task { await refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .foregroundStyle(Theme.gold)
                        .disabled(!backend.isConfigured)
                    }
                }
            }
        }
        .task { await refresh() }
    }

    // MARK: Config

    private var configCard: some View {
        GlassCard(title: "Payout Worker", icon: "server.rack", tint: Theme.verify) {
            VStack(alignment: .leading, spacing: 10) {
                Text("The Cloudflare Worker that pays women their 85% share and queues Apple refunds. Deploy steps live in backend/README.md.")
                    .font(.scaled(12, relativeTo: .caption1)).foregroundStyle(Theme.inkSoft)

                TextField("https://auctionbaby-payout.you.workers.dev", text: $backend.workerURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.scaled(13, weight: .medium, design: .monospaced, relativeTo: .footnote))
                    .foregroundStyle(Theme.ink)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))

                HStack(spacing: 8) {
                    Group {
                        if secretVisible {
                            TextField("Shared secret", text: $backend.sharedSecret)
                        } else {
                            SecureField("Shared secret", text: $backend.sharedSecret)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.scaled(13, weight: .medium, design: .monospaced, relativeTo: .footnote))
                    .foregroundStyle(Theme.ink)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))

                    Button { secretVisible.toggle() } label: {
                        Image(systemName: secretVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.scaled(13, relativeTo: .footnote)).foregroundStyle(Theme.inkSoft)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task { await testConnection() }
                } label: {
                    Label("Test connection", systemImage: "bolt.fill")
                        .font(.scaled(13, weight: .heavy, design: .rounded, relativeTo: .footnote))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.gold))
                }
                .buttonStyle(.plain)
                .disabled(!backend.isConfigured || loading)
            }
        }
    }

    // MARK: Float

    @ViewBuilder
    private var fundingCard: some View {
        if let f = funding {
            GlassCard(title: "Platform float", icon: "banknote.fill",
                      tint: f.topUpNeededUSD > 0 ? Theme.warning : Theme.success) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        stat("Balance", String(format: "%@ %.2f", f.currency.uppercased(), f.availableUSD))
                        Spacer()
                        stat("Target", String(format: "%@ %.2f", f.currency.uppercased(), f.bufferUSD))
                        Spacer()
                        stat("Dates today", "\(f.salesTodayCount)")
                    }
                    Text(f.topUpNeededUSD > 0
                         ? String(format: "Top up %@ %.2f to restore the buffer — the cron will pull it, or run it now below.", f.currency.uppercased(), f.topUpNeededUSD)
                         : "Float is healthy. Transfers to women will clear.")
                        .font(.scaled(12, relativeTo: .caption1))
                        .foregroundStyle(f.topUpNeededUSD > 0 ? Theme.warning : Theme.inkSoft)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.scaled(10, weight: .bold, design: .rounded, relativeTo: .caption2))
                .foregroundStyle(Theme.inkFaint)
            Text(value).font(.scaled(15, weight: .heavy, design: .rounded, relativeTo: .subheadline))
                .foregroundStyle(Theme.ink)
        }
    }

    // MARK: Owed women

    @ViewBuilder
    private var owedSection: some View {
        if !unfunded.isEmpty {
            SectionHeader(title: "Owed · \(unfunded.count)",
                          subtitle: "Failed transfers — fund the float, then pay each.")
                .padding(.top, 4)
            ForEach(unfunded) { entry in
                owedRow(entry)
            }
        }
    }

    private func owedRow(_ e: BackendService.UnfundedEntry) -> some View {
        let inFlight = paying.contains(e.id)
        return GlassSurface(corner: Theme.cornerL) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.ref?.isEmpty == false ? "Date \(e.ref!)" : "Date earnings")
                            .font(.scaled(13, weight: .bold, design: .rounded, relativeTo: .footnote))
                            .foregroundStyle(Theme.ink)
                        Text(e.accountId)
                            .font(.scaled(10, weight: .medium, design: .monospaced, relativeTo: .caption2))
                            .foregroundStyle(Theme.inkFaint).lineLimit(1)
                    }
                    Spacer()
                    Text(String(format: "$%.2f", e.amountUSD))
                        .font(.scaled(15, weight: .heavy, design: .rounded, relativeTo: .subheadline))
                        .foregroundStyle(Theme.warning)
                }
                Text(e.reason)
                    .font(.scaled(10, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint).lineLimit(2)
                Button {
                    Task { await pay(e) }
                } label: {
                    HStack(spacing: 6) {
                        if inFlight { ProgressView().tint(.black) }
                        Image(systemName: "banknote.fill").font(.scaled(12, relativeTo: .caption1))
                        Text(inFlight ? "Paying…" : "Pay now").fontWeight(.bold)
                    }
                    .font(.scaled(13, relativeTo: .footnote))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.success))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
            }
            .padding(14)
        }
    }

    // MARK: Tools

    private var toolsCard: some View {
        GlassCard(title: "Operator tools", icon: "wrench.and.screwdriver.fill", tint: Theme.gold) {
            VStack(spacing: 10) {
                NavigationLink { AdminLedgerView() } label: {
                    toolRow("Money ledger", icon: "list.bullet.rectangle.fill",
                            detail: "Every transfer, payout, top-up, refund and dispute.")
                }
                NavigationLink { AdminModerationView() } label: {
                    toolRow("Moderation queue", icon: "flag.fill",
                            detail: "In-app reports — Apple requires action within 24h.")
                }
                Divider().overlay(Color.white.opacity(0.08))
                HStack(spacing: 10) {
                    actionChip("Run top-up", icon: "arrow.up.circle.fill") {
                        await run { await backend.triggerTopUp() }
                    }
                    actionChip("Send digest", icon: "envelope.fill") {
                        await run { await backend.triggerDigest() }
                    }
                }
            }
        }
    }

    private func toolRow(_ title: String, icon: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.scaled(14, weight: .semibold, relativeTo: .footnote)).foregroundStyle(Theme.gold)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.gold.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.scaled(14, weight: .bold, design: .rounded, relativeTo: .footnote))
                    .foregroundStyle(Theme.ink)
                Text(detail).font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.scaled(12, weight: .bold, relativeTo: .caption1)).foregroundStyle(Theme.inkFaint)
        }
        .contentShape(Rectangle())
    }

    private func actionChip(_ title: String, icon: String,
                            action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: icon)
                .font(.scaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
                .foregroundStyle(Theme.gold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.gold.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    // MARK: Actions

    private func refresh() async {
        guard backend.isConfigured else { return }
        loading = true
        defer { loading = false }
        async let fundingResult = backend.fetchFunding()
        async let unfundedResult = backend.fetchUnfunded()
        switch await fundingResult {
        case .success(let f): funding = f; statusLine = nil
        case .failure(let message): setStatus(message, isError: true)
        }
        if case .success(let list) = await unfundedResult { unfunded = list }
    }

    private func testConnection() async {
        loading = true
        defer { loading = false }
        switch await backend.checkHealth() {
        case .success(let info):
            setStatus("Connected — \(info.service) v\(info.version).", isError: false)
            Haptics.success()
            await refresh()
        case .failure(let message):
            setStatus(message, isError: true)
            Haptics.warning()
        }
    }

    private func pay(_ e: BackendService.UnfundedEntry) async {
        paying.insert(e.id)
        defer { paying.remove(e.id) }
        if let err = await backend.manualFund(e) {
            setStatus(err, isError: true)
            Haptics.warning()
        } else {
            unfunded.removeAll { $0.id == e.id }   // cleared server-side too
            setStatus(String(format: "Paid $%.2f to %@.", e.amountUSD, e.accountId), isError: false)
            Haptics.success()
            await refresh()
        }
    }

    private func run(_ op: () async -> BackendResult<String>) async {
        loading = true
        defer { loading = false }
        switch await op() {
        case .success(let message): setStatus(message, isError: false); Haptics.success()
        case .failure(let message): setStatus(message, isError: true); Haptics.warning()
        }
    }

    private func setStatus(_ line: String, isError: Bool) {
        statusLine = line
        statusIsError = isError
    }
}
