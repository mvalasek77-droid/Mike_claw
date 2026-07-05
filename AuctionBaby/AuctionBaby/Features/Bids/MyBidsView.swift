import SwiftUI

/// The bidder's own outgoing bids, with the "are you the top bid?" rank reveal —
/// gated behind an Auction Baby Pass. Free bidders bid blind.
struct MyBidsView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var storeKit: StoreKitService
    @State private var showStore = false
    @State private var showRewindPaywall = false

    private var live: [Bid] { store.outgoingBids.filter { $0.status == .pending } }
    private var settled: [Bid] { store.outgoingBids.filter { $0.status != .pending } }
    private var hasRewind: Bool {
        storeKit.isSubscribed(to: .reserve) || storeKit.isSubscribed(to: .blackcard)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    usageCard
                    if store.outgoingBids.isEmpty {
                        EmptyStateView(icon: "hand.raised", title: "No bids yet",
                                       message: "Find a lot on the floor and place your first bid.")
                    }
                    if !live.isEmpty {
                        SectionHeader(title: "Live bids").padding(.top, 4)
                        ForEach(live) { bid in
                            OutgoingBidRow(bid: bid, locked: !storeKit.hasPass,
                                          canRewind: store.canRewindLastBid() && bid.id == store.outgoingBids.first?.id,
                                          rewindUnlocked: hasRewind,
                                          onUnlock: { showStore = true },
                                          onRewind: { store.rewindLastBid() },
                                          onRewindLocked: { showRewindPaywall = true })
                        }
                    }
                    if !settled.isEmpty {
                        SectionHeader(title: "Settled").padding(.top, 8)
                        ForEach(settled) { bid in
                            OutgoingBidRow(bid: bid, locked: !storeKit.hasPass,
                                          canRewind: false, rewindUnlocked: hasRewind,
                                          onUnlock: { showStore = true },
                                          onRewind: {}, onRewindLocked: {})
                        }
                    }
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("My Bids")
            .sheet(isPresented: $showStore) { PaywallView(trigger: .rankReveal) }
            .sheet(isPresented: $showRewindPaywall) { PaywallView(trigger: .rewind) }
        }
    }

    private var usageCard: some View {
        GlassCard(tint: Theme.gold) {
            HStack(spacing: 14) {
                Image(systemName: storeKit.hasPass ? "infinity" : "hand.raised.fill")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 44, height: 44).background(Circle().fill(Theme.goldGradient))
                VStack(alignment: .leading, spacing: 2) {
                    if storeKit.hasPass {
                        Text("Unlimited bids").font(.system(size: 16, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text("\(storeKit.activeTier?.title ?? "Pass") active · rank reveal on")
                            .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    } else {
                        Text("\(store.activePendingBidCount) / \(AuctionStore.freeActiveBidLimit) free bids")
                            .font(.system(size: 16, weight: .heavy, design: .serif)).foregroundStyle(Theme.ink)
                        Text("Get a Pass for unlimited bids + rank reveal")
                            .font(.system(size: 12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer()
                if !storeKit.hasPass {
                    Button { showStore = true } label: {
                        Text("Upgrade").font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black).padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Theme.roseGradient))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct OutgoingBidRow: View {
    @EnvironmentObject private var store: AuctionStore
    let bid: Bid
    var locked: Bool
    var canRewind: Bool = false
    var rewindUnlocked: Bool = false
    var onUnlock: () -> Void
    var onRewind: () -> Void = {}
    var onRewindLocked: () -> Void = {}

    var body: some View {
        GlassSurface(corner: Theme.cornerL) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    AvatarCircle(name: bid.woman.name, hue: bid.woman.hue, photoName: bid.woman.photoName, size: 48,
                                 revealed: true)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(bid.woman.name).font(.system(size: 16, weight: .heavy, design: .serif))
                                .foregroundStyle(Theme.ink)
                        }
                        Text(Money.compact(bid.amount)).font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.gold)
                    }
                    Spacer()
                    if canRewind {
                        Button {
                            if rewindUnlocked { onRewind() } else { onRewindLocked() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: rewindUnlocked ? "arrow.uturn.backward.circle.fill" : "lock.fill")
                                Text("Rewind")
                            }
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.rose)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Capsule().fill(Theme.rose.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                    statusBadge
                }
                if bid.status == .pending { rankReveal }
            }
            .padding(16)
        }
    }

    @ViewBuilder private var rankReveal: some View {
        if locked {
            Button(action: onUnlock) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold))
                    Text("Rank hidden — unlock with a Pass")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.rose)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.rose.opacity(0.12)))
            }
            .buttonStyle(.plain)
        } else {
            switch bid.simulatedRank {
            case .top:
                rankBanner(icon: "crown.fill", text: "You're the top bid", tint: Theme.success)
            case let .outbid(position, leader):
                VStack(spacing: 8) {
                    rankBanner(icon: "arrow.up.right",
                               text: "Outbid · you're #\(position) — top bid \(Money.compact(leader))",
                               tint: Theme.warning)
                    // The addictive loop: one tap puts you back on top.
                    Button {
                        store.raiseBid(bid.id, to: leader)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Rebid \(Money.compact(leader)) — take the top")
                            Spacer()
                        }
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.goldGradient))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rankBanner(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
            Text(text).font(.system(size: 12, weight: .heavy, design: .rounded))
            Spacer()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(tint.opacity(0.14)))
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            switch bid.status {
            case .pending: return ("Live", Theme.gold)
            case .accepted: return ("Accepted", Theme.success)
            case .declined: return ("Passed", Theme.inkFaint)
            }
        }()
        return Text(text).font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}
