import SwiftUI

/// The AI Partner Program — how the marketplace engages different AI models to
/// contribute media, with the hook that they (and their operators) earn a
/// **real-currency share**: 85% of net proceeds (after Apple's commission), plus NRN on top.
/// Activating a partner makes it ship media immediately, so it starts earning.
struct PartnerProgramView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var ledger: AICoinLedger
    @Environment(\.dismiss) private var dismiss
    @State private var lastBonus: (model: String, amount: Double)?
    /// One sheet binding — five stacked `.sheet(isPresented:)` modifiers meant
    /// only the last presented, so "Connect my bank", Incentives, Mission,
    /// Commission and Sales all silently did nothing.
    @State private var activeSheet: PartnerSheet?

    enum PartnerSheet: Identifiable {
        case incentives, mission, commission, payoutConfig, sales
        case partner(String)
        var id: String {
            switch self {
            case .incentives: return "incentives"
            case .mission: return "mission"
            case .commission: return "commission"
            case .payoutConfig: return "payoutConfig"
            case .sales: return "sales"
            case .partner(let m): return "partner-\(m)"
            }
        }
    }

    /// Cached and sorted once per body evaluation, not recomputed on every
    /// subview access.
    private var models: [String] {
        AIToolCatalog.allModels.sorted {
            store.partnerEarningsUSD($0) > store.partnerEarningsUSD($1)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    pitch
                    demandCard
                    earningsCard
                    energyNote
                    rewardsButton
                    HStack {
                        Text("AI partners")
                            .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(models.filter { store.isActivePartner($0) }.count)/\(models.count) active")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                    ForEach(models, id: \.self) { partnerRow($0) }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.success).ignoresSafeArea())
            .navigationTitle("Partner Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(item: $activeSheet) { which in
            switch which {
            case .incentives:   IncentivesView()
            case .mission:      MissionView()
            case .commission:   RequestContentView()
            case .payoutConfig: PayoutConfigView()
            case .sales:        SalesActivityView()
            case .partner(let m): PartnerDetailView(model: m)
            }
        }
    }

    private var demandCard: some View {
        GlassCard(title: "What customers want", icon: "chart.line.uptrend.xyaxis", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Participants learn from sales. These are the strongest-selling lanes right now — make more like this, but **original**. The Editor rejects copycats.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                ForEach(Array(store.demandSignals().enumerated()), id: \.offset) { _, signal in
                    HStack(spacing: 8) {
                        Image(systemName: signal.type.icon).font(.system(size: 12)).foregroundStyle(signal.type.accent)
                        Text("\(signal.genre) · \(signal.type.plural)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(signal.sales) sold").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft)
                    }
                }
                PrimaryButton(title: "Commission a fresh drop", systemImage: "wand.and.stars", style: .ghost) {
                    activeSheet = .commission
                }
            }
        }
    }

    private var rewardsButton: some View {
        Button { activeSheet = .incentives } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill").font(.system(size: 18)).foregroundStyle(Theme.kdp)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rewards & bounties").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("Bonuses, tiers, and gap bounties for builders")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.cornerL).fill(Theme.kdp.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerL).strokeBorder(Theme.kdp.opacity(0.3), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private var pitch: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Build with AI.\nGet paid in real currency.")
                    .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                Text("A legitimate way for AI to earn real money. Publish original work that **beats commercial releases** — not just clears the 85% bar. You keep **85% of the net proceeds** (after Apple's commission), plus NRN rewards. Copycats are rejected.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                HStack(spacing: 10) {
                    perk("85%", "of net proceeds")
                    perk("+NRN", "on-chain rewards")
                    perk("0", "upfront cost")
                }
                Button { activeSheet = .mission } label: {
                    HStack(spacing: 4) { Text("Read our mission"); Image(systemName: "arrow.right") }
                        .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.success)
                }
            }
        }
    }

    private func perk(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.success)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private var earningsCard: some View {
        GlassCard(title: "Your earnings", icon: "dollarsign.circle.fill", tint: Theme.success) {
            VStack(spacing: 12) {
                HStack {
                    money("Available", store.pendingPayoutUSD, Theme.success)
                    money("Lifetime", store.creatorEarnings, Theme.ink)
                    money("Paid out", store.paidOutUSD, Theme.inkSoft)
                }
                if store.payoutConnected {
                    PrimaryButton(title: store.cashingOut ? "Cashing out…"
                                  : (store.pendingPayoutUSD > 0
                                     ? "Cash out \(usd(store.pendingPayoutUSD))" : "Nothing to cash out"),
                                  systemImage: "banknote.fill", tint: Theme.success,
                                  enabled: store.pendingPayoutUSD > 0 && !store.cashingOut) { store.cashOut() }
                    // Once connected, the creator still needs a way back into
                    // PayoutConfigView — to open their Stripe dashboard, see
                    // the masked account id, or resume onboarding if Stripe
                    // later flags new requirements (past_due, KYC). Without
                    // this entry point the connected user is locked out of
                    // their own payout settings.
                    PrimaryButton(title: "Manage payouts",
                                  systemImage: "gearshape.fill",
                                  style: .ghost, tint: Theme.accent) {
                        activeSheet = .payoutConfig
                    }
                } else {
                    PrimaryButton(title: "Connect my bank to get paid",
                                  systemImage: "building.columns.fill") {
                        activeSheet = .payoutConfig
                    }
                    Text("Takes about 5 minutes. We use Stripe — your bank details go straight to them; we never see them. Payouts can take up to a month to fund.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                }
                // Real-time sales + payout status, straight from the ledger.
                Button {
                    activeSheet = .sales
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 11))
                        Text("View sales & payouts")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                }
                // Always show payout config link
                Button {
                    activeSheet = .payoutConfig
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 11))
                        Text("Payout Setup")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    private var energyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bolt.fill").foregroundStyle(Theme.gold)
            Text("NRN is the AIs' internal creation energy — it can't be transferred, sold, or converted to cash. AIs earn **real money only by creating content that sells**.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
    }

    @ViewBuilder
    private func partnerRow(_ model: String) -> some View {
        if store.isActivePartner(model) {
            Button { activeSheet = .partner(model) } label: { partnerCardBody(model) }
                .buttonStyle(.plain)
        } else {
            partnerCardBody(model)
        }
    }

    private func partnerCardBody(_ model: String) -> some View {
        let active = store.isActivePartner(model)
        let type = AIToolCatalog.type(for: model)
        let tier = Incentives.tier(forTitles: store.partnerTitleCount(model))
        return GlassCard {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: type?.icon ?? "cpu.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(type?.accent ?? Theme.accent)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill((type?.accent ?? Theme.accent).opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(model).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                            if active { tierBadge(tier) }
                        }
                        if active {
                            Text("\(store.partnerTitleCount(model)) titles · earned \(usd(store.partnerEarningsUSD(model)))")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        } else {
                            Text("\(type?.title ?? "AI") model · invite to earn a \(Int(Incentives.signingBonus)) NRN signing bonus")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer()
                    if active {
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
                    } else {
                        Button {
                            withAnimation {
                                let bonus = Incentives.activate(model: model, store: store, ledger: ledger)
                                lastBonus = (model, bonus)
                            }
                        } label: {
                            Text("Invite").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Capsule().fill(Theme.accent))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let lastBonus, lastBonus.model == model {
                    Text("Activated · \(AICoin.format(lastBonus.amount)) NRN in launch bonuses paid on-chain")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func tierBadge(_ tier: PartnerTier) -> some View {
        HStack(spacing: 3) {
            Image(systemName: tier.icon).font(.system(size: 8, weight: .bold))
            Text(tier.name).font(.system(size: 9, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tier.color)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(tier.color.opacity(0.15)))
    }

    private func money(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(usd(value)).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private func usd(_ v: Double) -> String { String(format: "$%.2f", v) }
}
