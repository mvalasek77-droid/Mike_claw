import SwiftUI

/// The lot's inbox. She sees each bidder's *stats* — archetype, Auction Credit,
/// deadbeat score, reviews — but his photo stays locked until she accepts.
struct IncomingBidsView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var matching: MatchingService
    @EnvironmentObject private var auth: AuthService
    @State private var detail: Bid?
    @State private var showSummon = false
    @State private var showActivity = false

    /// The inbox source — `remoteIncomingBids` when the woman is signed in
    /// with the matching Worker configured (slice 4b1b), otherwise the sim
    /// `incomingBids` (what Demo Mode uses).
    private var source: [Bid] {
        store.isRemoteInbox ? store.remoteIncomingBids : store.incomingBids
    }
    private var pending: [Bid] {
        source.filter { $0.status == .pending }
            .sorted { ($0.gilded ? 1 : 0, $0.amount) > ($1.gilded ? 1 : 0, $1.amount) }
    }
    private var resolved: [Bid] {
        source.filter { $0.status != .pending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    header
                    receiptsTip
                    LiveTicker()
                    DailyClaimCard()
                    if pending.isEmpty && resolved.isEmpty {
                        EmptyStateView(icon: "hand.raised", title: "No bids yet",
                                       message: store.isRemoteInbox
                                            ? "Bidders will land here when they place a real bid. Pull down to check for new ones."
                                            : "Bidders are finding their nerve. Summon one to see how it works.")
                    }
                    ForEach(Array(pending.enumerated()), id: \.element.id) { i, bid in
                        Button { detail = bid } label: { BidRow(bid: bid) }.buttonStyle(.plain)
                            // Only the first screen of rows animates in; later
                            // rows render statically so the rise-in never fires
                            // while the user is scrolling (that reads as jitter).
                            .riseIn(Double(i) * 0.05, active: i < 7)
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
                ToolbarItem(placement: .topBarLeading) {
                    ActivityBell(isPresented: $showActivity)
                }
                // Summon is a sim/Demo affordance — it mutates the sim
                // `incomingBids` array. On the remote inbox it would appear
                // to do nothing (the view reads `remoteIncomingBids`). Hide
                // the menu entirely when the inbox is remote so a signed-in
                // woman doesn't tap it and report a phantom bug.
                if !store.isRemoteInbox {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { store.summonBidder() } label: { Label("Summon a bidder", systemImage: "person.badge.plus") }
                            Button { store.summonBidder(trillionaire: true) } label: {
                                Label("Summon the Trillionaire ($1M bid)", systemImage: "crown.fill")
                            }
                        } label: { Image(systemName: "plus.circle.fill").foregroundStyle(Theme.gold) }
                    }
                }
            }
            .sheet(item: $detail) { bid in
                SuitorDetailView(bid: bid).presentationDetents([.large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showActivity) { ActivityView() }
            // Slice 4b1b — pull the real inbox from the matching Worker on
            // appear and via pull-to-refresh. No-op for Demo Mode / not-signed-in.
            .task(id: auth.serverUserId) {
                await store.refreshRemoteInbox(matching: matching)
            }
            .refreshable {
                await store.refreshRemoteInbox(matching: matching)
            }
        }
    }

    /// A one-liner explaining what these numbers actually are: the money he's
    /// promising to spend *on the date itself*, not a payment to her — with the
    /// operational advice ("keep the receipts") delivered as the punchline.
    private var receiptsTip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.scaled(14, weight: .bold, relativeTo: .footnote))
                .foregroundStyle(Theme.gold)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("What his bid actually means")
                    .font(.scaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
                    .tracking(0.4)
                    .foregroundStyle(Theme.ink)
                Text("It's what he'll spend on the date — dinner, drinks, the whole night. Not a payment to you. Keep the receipts (and enjoy them).")
                    .font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.gold.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerM).strokeBorder(Theme.gold.opacity(0.25), lineWidth: 1))
    }

    private var header: some View {
        GlassCard(tint: Theme.rose) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Highest live bid").font(.scaled(11, weight: .bold, design: .rounded, relativeTo: .caption2))
                        .foregroundStyle(Theme.inkFaint)
                    Text(pending.first.map { Money.compact($0.amount) } ?? "—")
                        .font(.scaled(28, weight: .heavy, design: .rounded, relativeTo: .title1)).foregroundStyle(Theme.gold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Accepted").font(.scaled(11, weight: .bold, design: .rounded, relativeTo: .caption2))
                        .foregroundStyle(Theme.inkFaint)
                    Text(Money.compact(store.earnings))
                        .font(.scaled(20, weight: .heavy, design: .rounded, relativeTo: .title3)).foregroundStyle(Theme.rose)
                }
            }
            HStack {
                if let floor = store.me.startingBid {
                    Chip(text: "Floor \(Money.full(floor))", systemImage: "dollarsign.circle.fill", color: Theme.gold)
                } else {
                    Chip(text: "No floor", systemImage: "lock.open.fill", color: Theme.rose)
                }
                Spacer()
                Text("Tap a bid to read his stats").font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint)
            }
        }
    }
}

/// A row in the inbox — stats forward, face hidden.
struct BidRow: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var matching: MatchingService
    let bid: Bid
    var dimmed: Bool = false

    var body: some View {
        GlassSurface(corner: Theme.cornerL) {
            VStack(spacing: 12) {
                if bid.isWhisper {
                    HStack(spacing: 5) {
                        Image(systemName: "ear.fill").font(.scaled(10, weight: .bold, relativeTo: .caption2))
                        Text("WHISPER").font(.scaled(10, weight: .heavy, design: .rounded, relativeTo: .caption2)).tracking(1)
                        Spacer()
                    }
                    .foregroundStyle(Theme.rose)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.rose.opacity(0.14)))
                } else if bid.gilded {
                    HStack(spacing: 5) {
                        Image(systemName: "seal.fill").font(.scaled(10, weight: .bold, relativeTo: .caption2))
                        Text("GILDED BID").font(.scaled(10, weight: .heavy, design: .rounded, relativeTo: .caption2)).tracking(1)
                        Spacer()
                    }
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.gold.opacity(0.14)))
                }
                HStack(spacing: 12) {
                    AvatarCircle(name: bid.man.name, hue: bid.man.hue, photoName: bid.man.photoName,
                                 remotePhotoURL: (bid.status == .accepted && !bid.isWhisper) ? bid.man.remotePhotoURLs.first : nil,
                                 size: 52, locked: bid.status != .accepted || bid.isWhisper, copycat: false)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(bid.isWhisper ? "Someone whispered"
                                 : bid.status == .accepted ? bid.man.name : "Hidden bidder")
                                .font(.scaled(16, weight: .heavy, design: .serif, relativeTo: .callout)).foregroundStyle(Theme.ink)
                            if !bid.isWhisper, bid.man.verified { VerifiedBadge(size: 14) }
                        }
                        if bid.isWhisper {
                            Text("Anonymous nod — nod back to draw a real bid.")
                                .font(.scaled(11, weight: .medium, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint)
                        } else {
                            ArchetypeBadge(archetype: bid.man.archetype, compact: true, pending: bid.man.showsPendingTrillionaire)
                        }
                    }
                    Spacer()
                    if !bid.isWhisper {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Money.compact(bid.amount))
                                .font(.scaled(22, weight: .heavy, design: .rounded, relativeTo: .title2)).foregroundStyle(Theme.gold)
                            if bid.qualifiesForMasterpiece {
                                Text("Masterpiece").font(.scaled(9, weight: .heavy, design: .rounded, relativeTo: .caption2))
                                    .foregroundStyle(Theme.rose)
                            }
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
                        Image(systemName: "quote.opening").font(.scaled(9, weight: .bold, relativeTo: .caption2))
                        Text("Replying to: \(ref)").font(.scaled(11, weight: .bold, design: .rounded, relativeTo: .caption2)).lineLimit(1)
                    }
                    .foregroundStyle(Theme.rose)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !bid.note.isEmpty {
                    Text("“\(bid.note)”").font(.scaled(13, weight: .medium, relativeTo: .footnote)).italic()
                        .foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity, alignment: .leading)
                }

                if bid.status == .pending {
                    if bid.isWhisper {
                        HStack(spacing: 10) {
                            Button {
                                Haptics.decline()
                                Task { await store.declineRemote(bid, matching: matching) }
                            } label: {
                                Label("Let it fade", systemImage: "xmark")
                                    .font(.scaled(14, weight: .bold, design: .rounded, relativeTo: .footnote))
                                    .foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                            }.buttonStyle(.plain)
                            Button {
                                Haptics.accept()
                                Task { await store.acceptRemote(bid, matching: matching) }
                            } label: {
                                Label("Nod back", systemImage: "hand.wave.fill")
                                    .font(.scaled(14, weight: .heavy, design: .rounded, relativeTo: .footnote))
                                    .foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.roseGradient))
                            }.buttonStyle(.plain)
                        }
                    } else {
                        HStack(spacing: 10) {
                            Button {
                                Haptics.decline()
                                Task { await store.declineRemote(bid, matching: matching) }
                            } label: {
                                Label("Pass", systemImage: "xmark")
                                    .font(.scaled(14, weight: .bold, design: .rounded, relativeTo: .footnote))
                                    .foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
                            }.buttonStyle(.plain)
                            Button {
                                Haptics.accept()
                                Task { await store.acceptRemote(bid, matching: matching) }
                            } label: {
                                Label("Accept", systemImage: "checkmark")
                                    .font(.scaled(14, weight: .heavy, design: .rounded, relativeTo: .footnote))
                                    .foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 11)
                                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.roseGradient))
                            }.buttonStyle(.plain)
                        }
                    }
                } else {
                    Text(bid.isWhisper ? (bid.status == .accepted ? "Nodded back" : "Faded")
                         : bid.status == .accepted ? "Accepted · invite sent" : "Passed")
                        .font(.scaled(12, weight: .bold, design: .rounded, relativeTo: .caption1))
                        .foregroundStyle(bid.status == .accepted ? Theme.success : Theme.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .opacity(dimmed ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bid.status == .accepted ? bid.man.name : "Hidden bidder"), \(Money.compact(bid.amount))\(bid.gilded ? ", gilded bid" : "")\(bid.man.verified ? ", verified" : ""), credit \(bid.man.auctionCredit)")
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
            Image(systemName: icon).font(.scaled(10, weight: .bold, relativeTo: .caption2))
            Text(value).font(.scaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
            Text(label).font(.scaled(10, weight: .semibold, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}
