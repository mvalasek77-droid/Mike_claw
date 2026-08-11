import SwiftUI

/// Where a bidder buys status. The price *is* the flex — the whole point is to
/// prove he has money. Trillionaire unlocks the ability to mint a Masterpiece.
struct ArchetypeStoreView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var storeKit: StoreKitService
    @State private var confirming: Archetype?

    /// The live StoreKit price for a money tier, falling back to the baked
    /// figure when products haven't loaded.
    private func priceLabel(_ tier: Archetype) -> String {
        guard let id = tier.productID else { return tier.fallbackPriceLabel }
        return storeKit.statusProducts.first { $0.id == id }?.displayPrice
            ?? tier.fallbackPriceLabel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    currentCard
                    SectionHeader(title: "Buy your rating",
                                  subtitle: "The bigger the tier, the louder the flex.")
                        .padding(.top, 4)
                    ForEach(Archetype.allCases) { tier in
                        ArchetypeRow(tier: tier,
                                     priceLabel: priceLabel(tier),
                                     current: store.me.archetype == tier,
                                     owned: tier.productID != nil && storeKit.owns(tier),
                                     pending: store.me.archetype == tier && store.me.showsPendingTrillionaire) {
                            confirming = tier
                        }
                    }
                    ladderNote
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("Status")
            .overlay { if storeKit.isWorking { workingOverlay } }
            .confirmationDialog(confirming.map { "Become a \($0.title)?" } ?? "",
                                isPresented: Binding(get: { confirming != nil },
                                                     set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible) {
                if let tier = confirming { confirmButtons(for: tier) }
                Button("Cancel", role: .cancel) { confirming = nil }
            } message: {
                if let tier = confirming { Text(tier.blurb) }
            }
        }
    }

    @ViewBuilder private func confirmButtons(for tier: Archetype) -> some View {
        switch tier.purchase {
        case .free:
            Button("Remove rating") { store.buyArchetype(tier); confirming = nil }
        case .money(let productID, _):
            if storeKit.owns(tier) {
                // Already paid for — non-consumables are owned forever.
                Button("Wear this badge") { store.buyArchetype(tier); confirming = nil }
            } else {
                Button("Buy for \(priceLabel(tier))") {
                    let target = tier
                    confirming = nil
                    Task {
                        guard let product = storeKit.statusProducts.first(where: { $0.id == productID }) else {
                            storeKit.errorMessage = "\(target.title) isn't available from the App Store right now."
                            return
                        }
                        // The grant hook equips the badge once Apple confirms.
                        await storeKit.purchase(product, appAccountToken: store.appAccountToken)
                    }
                }
            }
        }
    }

    /// Sets expectations before someone taps a four-figure button.
    private var ladderNote: some View {
        Text("Every rating is a real purchase, billed by Apple — the number is the whole point. Buy one and it's yours for good; you can switch between ratings you own any time, free. Gavels don't buy status: they're for Gilded Bids, Bid Insurance and streak freezes.")
            .font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8).padding(.top, 4)
    }

    private var workingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            ProgressView().controlSize(.large).tint(Theme.gold)
        }
    }

    /// What you're wearing now. Ratings are bought with real money, so there's
    /// deliberately no Gavel balance on this screen — Gavels buy Gilded Bids,
    /// Bid Insurance and streak freezes, never status.
    private var currentCard: some View {
        GlassCard(tint: Theme.gold) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your rating").font(.scaled(11, weight: .bold, design: .rounded, relativeTo: .caption2))
                        .foregroundStyle(Theme.inkFaint)
                    ArchetypeBadge(archetype: store.me.archetype,
                                   pending: store.me.showsPendingTrillionaire)
                }
                Spacer(minLength: 0)
            }
            if store.me.archetype == .none {
                Text("Unbadged. On this floor that's information too.")
                    .font(.scaled(12, relativeTo: .caption1)).foregroundStyle(Theme.inkSoft)
            }
        }
        .motion(Motion.snap, value: store.me.archetype)
    }
}

struct ArchetypeRow: View {
    let tier: Archetype
    var priceLabel: String = ""
    let current: Bool
    /// True only for real-money tiers the user has already bought.
    let owned: Bool
    var pending: Bool = false
    var onTap: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); onTap() }) {
            GlassSurface(corner: Theme.cornerL,
                         tint: tier.usesPrestigeStyle ? Theme.gold : .white) {
                HStack(spacing: 14) {
                    Image(systemName: tier.systemImage)
                        .font(.scaled(20, weight: .bold, relativeTo: .title3))
                        .foregroundStyle(tier.usesPrestigeStyle ? .black : tier.tint)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(tier.usesPrestigeStyle
                                                  ? AnyShapeStyle(Theme.prestigeGradient)
                                                  : AnyShapeStyle(tier.tint.opacity(0.16))))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(tier.title).font(.scaled(16, weight: .heavy, design: .serif, relativeTo: .callout))
                                .foregroundStyle(Theme.ink)
                            if tier == .trillionaire {
                                Image(systemName: "rosette").font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.rose)
                            }
                        }
                        Text(tier.blurb).font(.scaled(12, relativeTo: .caption1)).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 4) {
                        switch tier.purchase {
                        case .free:
                            Text("Free").font(.scaled(16, weight: .heavy, design: .rounded, relativeTo: .callout))
                                .foregroundStyle(Theme.ink)
                        case .money:
                            Text(owned ? "Owned" : priceLabel)
                                .font(.scaled(16, weight: .heavy, design: .rounded, relativeTo: .callout))
                                .foregroundStyle(owned ? Theme.success
                                                 : tier.usesPrestigeStyle ? Theme.gold : Theme.ink)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        if current {
                            Text(pending ? "PENDING" : "ACTIVE").font(.scaled(9, weight: .heavy, design: .rounded, relativeTo: .caption2))
                                .foregroundStyle(.black).padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(pending ? Theme.warning : Theme.success))
                        }
                    }
                }
                .padding(14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerL)
                    .strokeBorder(current ? (pending ? Theme.warning : Theme.success) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
