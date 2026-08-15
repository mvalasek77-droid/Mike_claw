import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var portfolio: PortfolioService
    @EnvironmentObject var store: StoreService
    @Environment(\.dismiss) private var dismiss

    var currentMembership: Membership { portfolio.user.membership }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    fairnessBanner
                    ForEach(Membership.paidTiers) { tier in
                        TierCard(tier: tier,
                                 isCurrent: tier == currentMembership,
                                 price: store.displayPrice(for: tier),
                                 isBuying: store.purchaseInFlight == tier) {
                            Task { await store.buy(tier) }
                            if !tier.isPaid { return }
                        }
                    }
                    if currentMembership.isPaid {
                        Button {
                            portfolio.downgradeToFree()
                        } label: {
                            Text("Cancel membership")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    restoreRow
                    fineprint
                }
                .padding()
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await store.loadProducts() }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("More coins. Same game.")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Every account starts with 1,000 Reel Coins and gets 500 RC refilled each week — always free. Subscribers get bigger bonuses and weekly allowances. Nothing else is gated: leaderboards, badges, and status are earned by winning calls, never bought.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var fairnessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "scale.3d")
                .foregroundStyle(.orange)
            Text("Status is not for sale. Tiers, badges, followers, and Featured Critics slots are still earned entirely on your calls.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.08)))
    }

    private var restoreRow: some View {
        Button {
            Task { await store.restore() }
        } label: {
            Text("Restore purchases")
                .font(.footnote)
        }
        .foregroundStyle(.orange)
        .padding(.top, 8)
    }

    private var fineprint: some View {
        Text("Subscriptions renew monthly at the price shown. Cancel any time in your App Store settings. Reel Coins are play-money and cannot be redeemed for cash or transferred. All prices are USD.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}

// MARK: - Tier card

private struct TierCard: View {
    let tier: Membership
    let isCurrent: Bool
    let price: String
    let isBuying: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.title3.bold())
                        .foregroundStyle(tier.accentColor)
                    Text(price)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                grantChip
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(tier.perks, id: \.self) { perk in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(tier.accentColor)
                            .font(.caption)
                            .padding(.top, 2)
                        Text(perk).font(.callout)
                    }
                }
            }

            Button(action: onTap) {
                if isBuying {
                    ProgressView().frame(maxWidth: .infinity)
                } else if isCurrent {
                    Text("Current plan").frame(maxWidth: .infinity)
                } else {
                    Text("Subscribe — \(price)").frame(maxWidth: .infinity).fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(isCurrent ? .gray : tier.accentColor)
            .disabled(isCurrent || isBuying)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(tier.accentColor.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isCurrent ? tier.accentColor : tier.accentColor.opacity(0.35),
                        lineWidth: isCurrent ? 2 : 1)
        )
    }

    private var grantChip: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("+\(Int(tier.startingBonus)) RC")
                .font(.caption.weight(.bold))
                .foregroundStyle(tier.accentColor)
            Text("\(Int(tier.weeklyAllowance)) / wk")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
