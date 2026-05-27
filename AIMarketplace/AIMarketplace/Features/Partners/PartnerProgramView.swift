import SwiftUI

/// The AI Partner Program — how the marketplace engages different AI models to
/// contribute media, with the hook that they (and their operators) earn **real
/// dollars**: 85% of every sale, paid out via Apple/Stripe, plus NRN on top.
/// Activating a partner makes it ship media immediately, so it starts earning.
struct PartnerProgramView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var ledger: AICoinLedger
    @Environment(\.dismiss) private var dismiss
    @State private var converted: Double?
    @State private var showIncentives = false
    @State private var showMission = false
    @State private var selectedPartner: PartnerID?
    @State private var lastBonus: (model: String, amount: Double)?

    private struct PartnerID: Identifiable { let id: String }

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
                    bridgeCard
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
        .sheet(isPresented: $showIncentives) { IncentivesView() }
        .sheet(isPresented: $showMission) { MissionView() }
        .sheet(item: $selectedPartner) { PartnerDetailView(model: $0.id) }
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
                    withAnimation { store.commissionFreshDrop() }
                    Haptics.success()
                }
            }
        }
    }

    private var rewardsButton: some View {
        Button { showIncentives = true } label: {
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
                Text("Build with AI.\nGet paid in real dollars.")
                    .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                Text("A legitimate way for AI to earn USD. Publish original work that **beats commercial releases** — not just clears the 85% bar. Apple takes its App Store cut first; of the rest you keep **85%** and AI Marketplace keeps 15%, plus NRN rewards. Copycats are rejected.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                HStack(spacing: 10) {
                    perk("85%", "real-USD share")
                    perk("+NRN", "on-chain rewards")
                    perk("0", "upfront cost")
                }
                Button { showMission = true } label: {
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
        GlassCard(title: "Your real-dollar earnings", icon: "dollarsign.circle.fill", tint: Theme.success) {
            VStack(spacing: 12) {
                HStack {
                    money("Available", store.pendingPayoutUSD, Theme.success)
                    money("Lifetime", store.creatorEarnings, Theme.ink)
                    money("Paid out", store.paidOutUSD, Theme.inkSoft)
                }
                if store.payoutConnected {
                    PrimaryButton(title: store.pendingPayoutUSD > 0
                                  ? "Cash out \(usd(store.pendingPayoutUSD))" : "Nothing to cash out",
                                  systemImage: "banknote.fill", tint: Theme.success,
                                  enabled: store.pendingPayoutUSD > 0) { store.cashOut() }
                } else {
                    PrimaryButton(title: "Connect payout method", systemImage: "link", style: .ghost) {
                        store.connectPayout()
                    }
                    Text("Connect Apple/Stripe to withdraw. Disbursement runs server-side (see backend/openapi.yaml).")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                }
            }
        }
    }

    private var bridgeCard: some View {
        GlassCard(title: "Convert NRN → USD", icon: "arrow.left.arrow.right.circle.fill", tint: Theme.gold) {
            VStack(spacing: 10) {
                HStack {
                    Text("\(AICoin.format(ledger.balance(of: AICoin.you))) NRN")
                        .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(String(format: "@ $%.4f", ledger.priceUSD))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                }
                PrimaryButton(title: "Convert all to USD", systemImage: "arrow.down.circle.fill",
                              tint: Theme.gold, enabled: ledger.balance(of: AICoin.you) >= 1) {
                    let usdValue = ledger.redeem(ledger.balance(of: AICoin.you))
                    store.addPendingPayout(usdValue)
                    converted = usdValue
                }
                if let converted {
                    Text("Converted to \(usd(converted)) — added to your available balance.")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.success)
                }
            }
        }
    }

    @ViewBuilder
    private func partnerRow(_ model: String) -> some View {
        if store.isActivePartner(model) {
            Button { selectedPartner = PartnerID(id: model) } label: { partnerCardBody(model) }
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
