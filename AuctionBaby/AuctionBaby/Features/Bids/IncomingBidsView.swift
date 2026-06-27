import SwiftUI

/// The lot's inbox. She sees each bidder's *stats* — archetype, Auction Credit,
/// deadbeat score, reviews — but his photo stays locked until she accepts.
struct IncomingBidsView: View {
    @EnvironmentObject private var store: AuctionStore
    @State private var detail: Bid?
    @State private var showSummon = false

    private var pending: [Bid] {
        store.incomingBids.filter { $0.status == .pending }
            .sorted { ($0.gilded ? 1 : 0, $0.amount) > ($1.gilded ? 1 : 0, $1.amount) }
    }
    private var resolved: [Bid] {
        store.incomingBids.filter { $0.status != .pending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    header
                    if pending.isEmpty && resolved.isEmpty {
                        EmptyStateView(icon: "hand.raised", title: "No bids yet",
                                       message: "Bidders are finding their nerve. Summon one to see how it works.")
                    }
                    ForEach(pending) { bid in
                        Button { detail = bid } label: { BidRow(bid: bid) }.buttonStyle(.plain)
                    }
                    if !resolved.isEmpty {
                        SectionHeader(title: "History").padding(.top, 8)
                        ForEach(resolved) { bid in BidRow(bid: bid, dimmed: true) }
                    }
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("Your Bids")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { store.summonBidder() } label: { Label("Summon a bidder", systemImage: "person.badge.plus") }
                        Button { store.summonBidder(trillionaire: true) } label: {
                            Label("Summon the Trillionaire ($9,999)", systemImage: "crown.fill")
                        }
                    } label: { Image(systemName: "plus.circle.fill").foregroundStyle(Theme.gold) }
                }
            }
            .sheet(item: $detail) { bid in
                SuitorDetailView(bid: bid).presentationDetents([.large])
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    private var header: some View {
        GlassCard(tint: Theme.rose) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Highest live bid").font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkFaint)
                    Text(pending.first.map { Money.compact($0.amount) } ?? "—")
                        .font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Accepted").font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkFaint)
                    Text(Money.compact(store.earnings))
                        .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Theme.rose)
                }
            }
            HStack {
                if let floor = store.me.startingBid {
                    Chip(text: "Floor \(Money.full(floor))", systemImage: "dollarsign.circle.fill", color: Theme.gold)
                } else {
                    Chip(text: "No floor", systemImage: "lock.open.fill", color: Theme.rose)
                }
                Spacer()
                Text("Tap a bid to read his stats").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
            }
        }
    }
}

/// A row in the inbox — stats forward, face hidden.
struct BidRow: View {
    @EnvironmentObject private var store: AuctionStore
    let bid: Bid
    var dimmed: Bool = false

    var body: some View {
        GlassSurface(corner: Theme.cornerL) {
            VStack(spacing: 12) {
                if bid.gilded {
                    HStack(spacing: 5) {
                        Image(systemName: "seal.fill").font(.system(size: 10, weight: .bold))
                        Text("GILDED BID").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1)
                        Spacer()
                    }
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.gold.opacity(0.14)))
                }
                HStack(spacing: 12) {
                    AvatarCircle(name: bid.man.name, hue: bid.man.hue, size: 52,
                                 locked: bid.status != .accepted, copycat: false)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(bid.status == .accepted ? bid.man.name : "Hidden bidder")
                                .font(.system(size: 16, weight: .heavy, design: .serif)).foregroundStyle(Theme.ink)
                            if bid.man.verified { VerifiedBadge(size: 14) }
                        }
                        ArchetypeBadge(archetype: bid.man.archetype, compact: true, pending: bid.man.showsPendingTrillionaire)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Money.compact(bid.amount))
                            .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                        if bid.qualifiesForMasterpiece {
                            Text("Masterpiece").font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.rose)
                        }
                    }
                }

                HStack(spacing: 8) {
                    StatPill(icon: "creditcard.fill", label: "Credit", value: "\(bid.man.auctionCredit)",
                             tint: creditTint(bid.man.auctionCredit))
                    DeadbeatTag(score: bid.man.deadbeatScore, compact: true)
                    Spacer()
                }

                if let ref = bid.promptRef {
                    HStack(spacing: 5) {
                        Image(systemName: "quote.opening").font(.system(size: 9, weight: .bold))
                        Text("Replying to: \(ref)").font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
                    }
                    .foregroundStyle(Theme.rose)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !bid.note.isEmpty {
                    Text("“\(bid.note)”").font(.system(size: 13, weight: .medium)).italic()
                        .foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity, alignment: .leading)
                }

                if bid.status == .pending {
                    HStack(spacing: 10) {
                        Button { store.decline(bid) } label: {
                            Label("Pass", systemImage: "xmark")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                        }.buttonStyle(.plain)
                        Button { store.accept(bid) } label: {
                            Label("Accept", systemImage: "checkmark")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.roseGradient))
                        }.buttonStyle(.plain)
                    }
                } else {
                    Text(bid.status == .accepted ? "Accepted · invite sent" : "Passed")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(bid.status == .accepted ? Theme.success : Theme.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .opacity(dimmed ? 0.55 : 1)
    }

    private func creditTint(_ v: Int) -> Color {
        switch v { case 740...: return Theme.success; case 670..<740: return Theme.gold; default: return Theme.warning }
    }
}

/// Small labelled stat pill.
struct StatPill: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = Theme.gold
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(value).font(.system(size: 12, weight: .heavy, design: .rounded))
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.inkFaint)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}
