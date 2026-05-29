import SwiftUI

/// Rewards, bounties and tiers — the incentive structure that pulls AIs toward
/// building up the marketplace (quality, and toward gaps), all paid in NRN on
/// top of the 85% real-currency share.
struct IncentivesView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var ledger: AICoinLedger
    @Environment(\.dismiss) private var dismiss

    private var bounties: [Bounty] { Incentives.activeBounties(in: store.catalog) }

    private var leaderboard: [String] {
        AIToolCatalog.allModels
            .filter { store.isActivePartner($0) }
            .sorted {
                if store.partnerTitleCount($0) != store.partnerTitleCount($1) {
                    return store.partnerTitleCount($0) > store.partnerTitleCount($1)
                }
                return store.partnerEarningsUSD($0) > store.partnerEarningsUSD($1)
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    bonusRules
                    if !bounties.isEmpty { bountiesCard }
                    tiersCard
                    leaderboardCard
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.kdp).ignoresSafeArea())
            .navigationTitle("Rewards & Bounties")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var bonusRules: some View {
        GlassCard(title: "How AIs earn NRN", icon: "gift.fill", tint: Theme.gold) {
            VStack(spacing: 10) {
                rule("Signing bonus", "On activation", Incentives.signingBonus)
                rule("Per title shipped", "Scaled by your tier", Incentives.perTitleBonus)
                rule("Quality bonus", "Each title scoring \(Incentives.qualityScore)+", Incentives.qualityBonus)
                rule("Gap bounty", "Fill a thin category", Incentives.bountyReward)
            }
        }
    }

    private func rule(_ title: String, _ detail: String, _ nrn: Double) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                Text(detail).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Text("+\(AICoin.format(nrn)) NRN")
                .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
        }
    }

    private var bountiesCard: some View {
        GlassCard(title: "Active bounties", icon: "target", tint: Theme.warning) {
            VStack(spacing: 14) {
                ForEach(bounties) { bounty in
                    VStack(spacing: 6) {
                        HStack {
                            Image(systemName: bounty.type.icon).font(.system(size: 13)).foregroundStyle(bounty.type.accent)
                            Text("Ship a \(bounty.type.title.lowercased()) to help fill the catalogue")
                                .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("+\(AICoin.format(bounty.reward))")
                                .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.warning)
                        }
                        GeometryReader { geo in
                            Capsule().fill(.white.opacity(0.08)).overlay(alignment: .leading) {
                                Capsule().fill(bounty.type.accent).frame(width: geo.size.width * bounty.progress)
                            }
                        }
                        .frame(height: 5)
                        Text("\(bounty.current)/\(bounty.target) titles")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkFaint)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var tiersCard: some View {
        GlassCard(title: "Builder tiers", icon: "chart.line.uptrend.xyaxis", tint: Theme.success) {
            VStack(spacing: 12) {
                ForEach(Incentives.tiers, id: \.name) { tier in
                    HStack(spacing: 12) {
                        Image(systemName: tier.icon).font(.system(size: 14)).foregroundStyle(tier.color)
                            .frame(width: 30, height: 30).background(Circle().fill(tier.color.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tier.name).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                            Text(tier.perk).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%g×", tier.multiplier))
                                .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(tier.color)
                            Text("\(tier.minTitles)+ titles").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkFaint)
                        }
                    }
                }
            }
        }
    }

    private var leaderboardCard: some View {
        GlassCard(title: "Top builders", icon: "trophy.fill", tint: Theme.gold) {
            VStack(spacing: 12) {
                ForEach(Array(leaderboard.prefix(10).enumerated()), id: \.element) { index, model in
                    let tier = Incentives.tier(forTitles: store.partnerTitleCount(model))
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundStyle(index < 3 ? Theme.gold : Theme.inkFaint).frame(width: 22)
                        Image(systemName: tier.icon).font(.system(size: 11)).foregroundStyle(tier.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                            Text("\(store.partnerTitleCount(model)) titles · \(tier.name)")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "$%.0f", store.partnerEarningsUSD(model)))
                                .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.success)
                            Text("\(AICoin.format(ledger.cycled(of: model))) NRN cycled")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.gold)
                        }
                    }
                }
            }
        }
    }
}
