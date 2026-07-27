import SwiftUI

/// Where a bidder buys status. The price *is* the flex — the whole point is to
/// prove he has money. Trillionaire unlocks the ability to mint a Masterpiece.
struct ArchetypeStoreView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var storeKit: StoreKitService
    @State private var confirming: Archetype?
    @State private var showStore = false

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
                    walletCard
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
            .sheet(isPresented: $showStore) {
                GavelStoreView().presentationDetents([.large])
            }
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
        case .gavels(let cost):
            Button("Spend \(Tally.compact(cost)) Gavels") {
                store.buyArchetype(tier); confirming = nil
            }
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
        Text("The top four ratings are real purchases, billed by Apple — that's the point of them. Buy one once and it's yours for good; you can switch back to it any time for free. The lower ratings are paid in Gavels.")
            .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8).padding(.top, 4)
    }

    private var workingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            ProgressView().controlSize(.large).tint(Theme.gold)
        }
    }

    private var walletCard: some View {
        GlassCard(tint: Theme.gold) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Gavels").font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkFaint)
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.gold)
                        Text(Tally.compact(store.wallet)).font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.gold).contentTransition(.numericText())
                    }
                }
                Spacer()
                Button { showStore = true } label: {
                    Label("Top up", systemImage: "plus")
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(Theme.goldGradient))
                }.buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text("Current:").font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                ArchetypeBadge(archetype: store.me.archetype, compact: true, pending: store.me.showsPendingTrillionaire)
            }
        }
        .motion(Motion.snap, value: store.wallet)
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
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(tier.usesPrestigeStyle ? .black : tier.tint)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(tier.usesPrestigeStyle
                                                  ? AnyShapeStyle(Theme.prestigeGradient)
                                                  : AnyShapeStyle(tier.tint.opacity(0.16))))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(tier.title).font(.system(size: 16, weight: .heavy, design: .serif))
                                .foregroundStyle(Theme.ink)
                            if tier == .trillionaire {
                                Image(systemName: "rosette").font(.system(size: 11)).foregroundStyle(Theme.rose)
                            }
                        }
                        Text(tier.blurb).font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 4) {
                        switch tier.purchase {
                        case .free:
                            Text("Free").font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.ink)
                        case .gavels(let cost):
                            // Gavels get the hammer; real money never does, so
                            // the two economies can't be confused at a glance.
                            HStack(spacing: 3) {
                                Image(systemName: "hammer.fill").font(.system(size: 11, weight: .bold))
                                Text(Tally.compact(cost)).font(.system(size: 16, weight: .heavy, design: .rounded))
                            }
                            .foregroundStyle(Theme.ink)
                        case .money:
                            Text(owned ? "Owned" : priceLabel)
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(owned ? Theme.success
                                                 : tier.usesPrestigeStyle ? Theme.gold : Theme.ink)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        if current {
                            Text(pending ? "PENDING" : "ACTIVE").font(.system(size: 9, weight: .heavy, design: .rounded))
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
