import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var portfolio: PortfolioService
    @EnvironmentObject var store: StoreService
    @Environment(\.dismiss) private var dismiss

    @State private var showErrorAlert = false

    var currentMembership: Membership { portfolio.user.membership }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    fairnessBanner

                    switch store.loadState {
                    case .loading, .idle:
                        loadingCard
                    case .failed, .empty:
                        unavailableCard
                    case .loaded:
                        tierStack
                    }

                    if currentMembership.isPaid {
                        Button {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Manage subscription in App Store")
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
                    // Review device labels this as the visible exit. Always
                    // visible, even when the StoreKit load is stuck, so the
                    // sheet can never trap the user.
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("paywall.close")
                }
            }
            .task { await store.loadProducts() }
            .onChange(of: store.lastError) { _, newValue in
                showErrorAlert = (newValue?.isEmpty == false)
            }
            .alert("Can't complete this",
                   isPresented: $showErrorAlert,
                   presenting: store.lastError) { _ in
                Button("OK") { store.clearLastError() }
            } message: { message in
                Text(message)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Better tools. A badge by your name.")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Every player — free or paid — trades the same 1,000 RC stake each week, so the leaderboard measures skill. Memberships add early access to new markets, limit orders, performance stats, Pro analytics, history export, exclusive app icons and a badge next to your name.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var fairnessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "scale.3d")
                .foregroundStyle(.orange)
            Text("Status is not for sale. No plan adds Reel Coins. Trader ranks like Insider and Studio Head, leaderboard spots and the review spotlight are earned only by trading profit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.08)))
    }

    /// Shown while StoreKit is still responding. Critically, the Close
    /// button in the toolbar is still live — so even a stuck fetch can
    /// never prevent the reviewer from leaving the sheet.
    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .accessibilityIdentifier("paywall.loading")
            Text("Loading subscription options…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    /// Shown when StoreKit returned no products, or when the fetch
    /// failed. Gives the reviewer a visible explanation, a working
    /// Retry button, and the Close button in the toolbar still works.
    private var unavailableCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title)
                .foregroundStyle(.orange)
            Text("Subscriptions are unavailable right now.")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.reloadProducts() }
            } label: {
                if store.isLoadingProducts {
                    ProgressView().tint(.white)
                } else {
                    Text("Retry").frame(maxWidth: 160)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityIdentifier("paywall.retry")
            .disabled(store.isLoadingProducts)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private var explanation: String {
        switch store.loadState {
        case .failed:
            return "We couldn't reach the App Store. Check your connection and try again."
        default:
            return "The App Store hasn't finished listing our plans yet. Try again in a few minutes."
        }
    }

    @ViewBuilder
    private var tierStack: some View {
        ForEach(Membership.paidTiers) { tier in
            TierCard(tier: tier,
                     isCurrent: tier == currentMembership,
                     price: store.displayPrice(for: tier),
                     isBuying: store.purchaseInFlight == tier,
                     canPurchase: store.canPurchase(tier)) {
                Task { await store.buy(tier) }
            }
        }
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
        VStack(spacing: 8) {
            Text("Subscriptions renew monthly at the price shown. Cancel any time in your App Store settings. Reel Coins are play-money and cannot be redeemed for cash, transferred between accounts, or exchanged for anything of value. All prices are USD.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Apple requires functional links to both documents wherever
            // an auto-renewing subscription is offered (Guideline 3.1.2).
            // They have to be in the binary, not only on the website.
            HStack(spacing: 6) {
                NavigationLink { LegalView(kind: .terms) } label: {
                    Text("Terms of Service").font(.caption2.weight(.semibold))
                }
                Text("·").font(.caption2).foregroundStyle(.tertiary)
                NavigationLink { LegalView(kind: .privacy) } label: {
                    Text("Privacy Policy").font(.caption2.weight(.semibold))
                }
            }
            .tint(Theme.marqueeGold)
        }
        .padding(.top, 4)
    }
}

// MARK: - Tier card

private struct TierCard: View {
    let tier: Membership
    let isCurrent: Bool
    let price: String
    let isBuying: Bool
    let canPurchase: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tier.displayName)
                            .font(.title3.bold())
                            .foregroundStyle(tier.accentColor)
                        if let icon = tier.badgeIcon {
                            Image(systemName: icon)
                                .font(.caption)
                                .foregroundStyle(tier.accentColor)
                        }
                    }
                    Text(price)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
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
                } else if !canPurchase {
                    Text("Unavailable").frame(maxWidth: .infinity).fontWeight(.semibold)
                } else {
                    Text("Subscribe — \(price)").frame(maxWidth: .infinity).fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(isCurrent || !canPurchase ? .gray : tier.accentColor)
            .disabled(isCurrent || isBuying || !canPurchase)
            .accessibilityIdentifier("paywall.subscribe.\(tier.rawValue)")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(tier.accentColor.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isCurrent ? tier.accentColor : tier.accentColor.opacity(0.35),
                        lineWidth: isCurrent ? 2 : 1)
        )
    }
}
