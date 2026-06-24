import SwiftUI

/// The bidder's home: a Hinge-style vertical feed of women on the floor. Each
/// card is a tappable lot; copycats are flagged in place.
struct AuctionFeedView: View {
    @EnvironmentObject private var store: AuctionStore
    @State private var bidTarget: Profile?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    header
                    ForEach(store.floor) { woman in
                        NavigationLink(value: woman) {
                            FloorCard(woman: woman) { bidTarget = woman }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 24)
                }
                .screenPadding()
                .padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("The Floor")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Profile.self) { woman in
                AuctioneeDetailView(woman: woman) { bidTarget = woman }
            }
            .sheet(item: $bidTarget) { woman in
                BidSheet(woman: woman)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tonight's lots")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "hammer.fill").font(.system(size: 11, weight: .bold))
                    Text(Tally.compact(store.wallet))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Theme.gold.opacity(0.14)))
            }
            Text("Bid what a date is worth. She unlocks your photo when she accepts.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One lot in the feed.
struct FloorCard: View {
    let woman: Profile
    var onBid: () -> Void

    var body: some View {
        GlassSurface(corner: Theme.cornerXL) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    AvatarView(name: woman.name, hue: woman.hue, copycat: woman.isCopycat,
                               copycatStyle: woman.copycatStyle, corner: Theme.cornerXL)
                        .frame(height: 360)

                    if woman.isCopycat {
                        CopycatTag().padding(12)
                    }
                    if woman.masterpiece {
                        VStack { Spacer(); HStack { Spacer(); MasterpieceBadge(compact: true) } }
                            .padding(12)
                    }

                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                        .frame(height: 360)
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 6) {
                        Spacer()
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(woman.name)
                                .font(.system(size: 26, weight: .heavy, design: .serif))
                            Text("\(woman.age)")
                                .font(.system(size: 20, weight: .medium, design: .serif))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .foregroundStyle(Theme.ink)
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse").font(.system(size: 11))
                            Text(woman.location).font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: 360, alignment: .bottomLeading)
                }

                VStack(alignment: .leading, spacing: 12) {
                    if !woman.bio.isEmpty {
                        Text(woman.bio)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let prompt = woman.prompts.first {
                        PromptBubble(prompt: prompt)
                    }

                    HStack {
                        FloorStat(woman: woman)
                        Spacer()
                        Button(action: onBid) {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.raised.fill")
                                Text("Bid")
                            }
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(Capsule().fill(Theme.goldGradient))
                            .depth(40, strong: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
    }
}

/// Compact floor / value readout shown on each card.
struct FloorStat: View {
    let woman: Profile
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let bid = woman.startingBid {
                Text("Starting bid").font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkFaint)
                Text(Money.full(bid)).font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
            } else {
                Text("No floor").font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkFaint)
                Text("Open bidding").font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.rose)
            }
        }
    }
}

/// Hinge-style prompt bubble.
struct PromptBubble: View {
    let prompt: Prompt
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(prompt.question)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            Text(prompt.answer)
                .font(.system(size: 17, weight: .bold, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerM).strokeBorder(Theme.hairline, lineWidth: 0.6))
    }
}
