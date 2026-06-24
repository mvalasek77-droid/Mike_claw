import SwiftUI

/// Where a bidder buys status. The price *is* the flex — the whole point is to
/// prove he has money. Trillionaire unlocks the ability to mint a Masterpiece.
struct ArchetypeStoreView: View {
    @EnvironmentObject private var store: AuctionStore
    @State private var confirming: Archetype?
    @State private var showStore = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    walletCard
                    SectionHeader(title: "Buy your rating",
                                  subtitle: "Spend Gavels. The bigger the tier, the louder the flex.")
                        .padding(.top, 4)
                    ForEach(Archetype.allCases) { tier in
                        ArchetypeRow(tier: tier,
                                     current: store.me.archetype == tier,
                                     owned: store.me.archetype.rawValue >= tier.rawValue && tier != .none,
                                     pending: store.me.archetype == tier && store.me.showsPendingTrillionaire) {
                            confirming = tier
                        }
                    }
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("Status")
            .sheet(isPresented: $showStore) {
                GavelStoreView().presentationDetents([.large])
            }
            .confirmationDialog(confirming.map { "Become a \($0.title)?" } ?? "",
                                isPresented: Binding(get: { confirming != nil },
                                                     set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible) {
                if let tier = confirming {
                    Button(tier == .none ? "Remove rating" : "Spend \(Tally.compact(tier.price)) Gavels") {
                        store.buyArchetype(tier); confirming = nil
                    }
                    Button("Cancel", role: .cancel) { confirming = nil }
                }
            } message: {
                if let tier = confirming { Text(tier.blurb) }
            }
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
    let current: Bool
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
                        if tier == .none {
                            Text("Free").font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.ink)
                        } else {
                            HStack(spacing: 3) {
                                Image(systemName: "hammer.fill").font(.system(size: 11, weight: .bold))
                                Text(Tally.compact(tier.price)).font(.system(size: 16, weight: .heavy, design: .rounded))
                            }
                            .foregroundStyle(tier.usesPrestigeStyle ? Theme.gold : Theme.ink)
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
