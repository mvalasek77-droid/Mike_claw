import SwiftUI

/// Where a bidder buys status. The price *is* the flex — the whole point is to
/// prove he has money. Trillionaire unlocks the ability to mint a Masterpiece.
struct ArchetypeStoreView: View {
    @EnvironmentObject private var store: AuctionStore
    @State private var confirming: Archetype?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    walletCard
                    SectionHeader(title: "Buy your rating",
                                  subtitle: "The more you pay, the louder the flex.")
                        .padding(.top, 4)
                    ForEach(Archetype.allCases) { tier in
                        ArchetypeRow(tier: tier,
                                     current: store.me.archetype == tier,
                                     owned: store.me.archetype.rawValue >= tier.rawValue && tier != .none) {
                            confirming = tier
                        }
                    }
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("Status")
            .confirmationDialog(confirming.map { "Become a \($0.title)?" } ?? "",
                                isPresented: Binding(get: { confirming != nil },
                                                     set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible) {
                if let tier = confirming {
                    Button(tier == .none ? "Remove rating" : "Pay \(Money.full(tier.price))") {
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
                    Text("Demo credits").font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkFaint)
                    Text(Money.full(store.wallet)).font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.gold).contentTransition(.numericText())
                }
                Spacer()
                Button { store.addDemoCredits() } label: {
                    Label("Top up", systemImage: "plus")
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(Theme.goldGradient))
                }.buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Text("Current:").font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                ArchetypeBadge(archetype: store.me.archetype, compact: true)
            }
        }
        .motion(Motion.snap, value: store.wallet)
    }
}

struct ArchetypeRow: View {
    let tier: Archetype
    let current: Bool
    let owned: Bool
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
                        Text(tier == .none ? "Free" : Money.compact(tier.price))
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(tier.usesPrestigeStyle ? Theme.gold : Theme.ink)
                        if current {
                            Text("ACTIVE").font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black).padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.success))
                        }
                    }
                }
                .padding(14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerL)
                    .strokeBorder(current ? Theme.success : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
