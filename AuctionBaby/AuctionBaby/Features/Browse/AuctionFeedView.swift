import SwiftUI
import UIKit

/// The bidder's home: a Hinge-style vertical feed of women on the floor. Each
/// card is a tappable lot; copycats are flagged in place.
struct AuctionFeedView: View {
    @EnvironmentObject private var store: AuctionStore
    @State private var bidTarget: Profile?
    @State private var showFilters = false
    @State private var showActivity = false
    @State private var showLotOfDay = false

    private var lots: [Profile] { store.filteredFloor.filter { $0.id != store.lotOfTheDay?.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    header
                    LiveTicker()
                    DailyClaimCard()
                    if let star = store.lotOfTheDay {
                        NavigationLink(value: star) { LotOfTheDayBanner(woman: star) }
                            .buttonStyle(.plain)
                            .riseIn(0.05)
                    }
                    if lots.isEmpty && store.lotOfTheDay == nil {
                        EmptyStateView(icon: "line.3.horizontal.decrease.circle",
                                       title: "No lots match",
                                       message: "Your filters are hiding everyone. Loosen them to see more of the floor.")
                    }
                    ForEach(Array(lots.enumerated()), id: \.element.id) { i, woman in
                        NavigationLink(value: woman) {
                            FloorCard(woman: woman) { bidTarget = woman }
                        }
                        .buttonStyle(.plain)
                        .riseIn(Double(min(i, 6)) * 0.06)
                    }
                    Spacer(minLength: 24)
                }
                .screenPadding()
                .padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("The Floor")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ActivityBell(isPresented: $showActivity)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal.decrease.circle\(store.filters.activeCount > 0 ? ".fill" : "")")
                                .font(.system(size: 17, weight: .semibold))
                            if store.filters.activeCount > 0 {
                                Text("\(store.filters.activeCount)")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.black).frame(width: 14, height: 14)
                                    .background(Circle().fill(Theme.rose)).offset(x: 6, y: -6)
                            }
                        }
                        .foregroundStyle(Theme.gold)
                    }
                }
            }
            .navigationDestination(for: Profile.self) { woman in
                AuctioneeDetailView(woman: woman) { bidTarget = woman }
            }
            .sheet(item: $bidTarget) { woman in
                BidSheet(woman: woman)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showFilters) {
                FiltersView().presentationDetents([.large])
            }
            .sheet(isPresented: $showActivity) { ActivityView() }
            .sheet(isPresented: $showLotOfDay) {
                if let lot = store.lotOfTheDay {
                    LotOfTheDayIntroSheet(woman: lot) { profile in
                        showLotOfDay = false
                        if let profile { bidTarget = profile }
                    }
                    .presentationDetents([.large])
                }
            }
            .onAppear {
                if store.shouldShowLotOfDayIntro {
                    showLotOfDay = true
                    store.markLotOfDaySeen()
                }
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
                if store.isBoosted, let until = store.boostUntil {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold))
                        Text(timerInterval: Date.now...max(until, Date.now.addingTimeInterval(1)), countsDown: true)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Theme.rose)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.rose.opacity(0.16)))
                }
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

/// The curated "Lot of the Day" — a premium gold-framed hero above the floor
/// (Auction Baby's answer to Hinge Standouts). Rendered inline in the feed;
/// the full-screen intro variant is `LotOfTheDayIntroSheet`.
struct LotOfTheDayBanner: View {
    let woman: Profile
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill").font(.system(size: 11, weight: .bold))
                Text("LOT OF THE DAY").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.5)
                Spacer()
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.goldGradient)

            ZStack(alignment: .bottomLeading) {
                AvatarView(name: woman.name, hue: woman.hue, photoName: woman.photoName, corner: 0)
                    .frame(height: 240)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                    .frame(height: 240).allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(woman.name).font(.system(size: 26, weight: .heavy, design: .serif))
                        if woman.verified { VerifiedBadge(size: 18) }
                        if woman.masterpiece { MasterpieceBadge(compact: true) }
                    }
                    .foregroundStyle(Theme.ink)
                    HStack(spacing: 8) {
                        ArtTierBadge(tier: woman.artTier, compact: true)
                        Chip(text: "Showcase \(woman.showcaseCredit)", systemImage: "rosette", color: Theme.rose)
                        Chip(text: Money.compact(woman.marketValue), systemImage: "dollarsign.circle.fill", color: Theme.gold)
                    }
                }
                .padding(16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerXL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerXL, style: .continuous)
                .strokeBorder(Theme.goldGradient, lineWidth: 1.5)
        )
        .depth(Theme.cornerXL, strong: true)
        .shadow(color: Theme.gold.opacity(shimmer ? 0.45 : 0.2), radius: shimmer ? 18 : 10)
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) { shimmer = true }
        }
    }
}

/// The once-a-day full-screen showcase of the Lot of the Day. Fires on the
/// first feed open of the calendar day and never again that day. Tapping
/// "Place a bid" dismisses and opens the BidSheet; anything else dismisses
/// silently.
struct LotOfTheDayIntroSheet: View {
    let woman: Profile
    var onDismiss: (Profile?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var appear = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    Button { onDismiss(nil); dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Label("TONIGHT'S LOT", systemImage: "hammer.fill")
                        .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(2)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.goldGradient))
                    Text("Curated for tonight only")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkFaint)
                }

                ZStack(alignment: .bottomLeading) {
                    AvatarView(name: woman.name, hue: woman.hue,
                               photoName: woman.photoName, photoData: woman.photoData,
                               corner: Theme.cornerXL)
                        .frame(height: 380)
                    LinearGradient(colors: [.clear, .black.opacity(0.85)],
                                   startPoint: .center, endPoint: .bottom)
                        .frame(height: 380).allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(woman.name)
                                .font(.system(size: 32, weight: .heavy, design: .serif))
                            if woman.verified { VerifiedBadge(size: 20) }
                            Text("\(woman.age)")
                                .font(.system(size: 22, weight: .medium, design: .serif))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .foregroundStyle(Theme.ink)
                        HStack(spacing: 8) {
                            ArtTierBadge(tier: woman.artTier, compact: true)
                            Chip(text: "Showcase \(woman.showcaseCredit)",
                                 systemImage: "rosette", color: Theme.rose)
                        }
                        Text(woman.location)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(20)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerXL, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerXL, style: .continuous)
                        .strokeBorder(Theme.goldGradient, lineWidth: 1.5)
                )
                .scaleEffect(appear ? 1 : 0.94)
                .opacity(appear ? 1 : 0)

                if let prompt = woman.prompts.first {
                    PromptBubble(prompt: prompt).opacity(appear ? 1 : 0)
                }

                PrimaryButton(title: "Place a bid on \(woman.name)",
                              systemImage: "hand.raised.fill",
                              gradient: Theme.goldGradient) {
                    onDismiss(woman); dismiss()
                }
                .opacity(appear ? 1 : 0)

                Button {
                    onDismiss(nil); dismiss()
                } label: {
                    Text("Browse the floor instead")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 24)
            }
            .screenPadding()
        }
        .background(AppBackground())
        .onAppear {
            Motion.run(.spring(response: 0.55, dampingFraction: 0.75)) { appear = true }
        }
    }
}

/// A pulsing green dot for the "On the Floor Now" live signal.
struct LivePulseDot: View {
    @State private var pulse = false
    var body: some View {
        Circle().fill(Theme.success)
            .frame(width: 8, height: 8)
            .overlay(
                Circle().stroke(Theme.success.opacity(pulse ? 0.0 : 0.6),
                                lineWidth: pulse ? 4 : 1)
            )
            .onAppear {
                guard !UIAccessibility.isReduceMotionEnabled else { return }
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
            .accessibilityHidden(true)
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
                    AvatarView(name: woman.name, hue: woman.hue, photoName: woman.photoName,
                               corner: Theme.cornerXL)
                        .frame(height: 360)

                    if woman.isOnTheFloorNow {
                        HStack(spacing: 5) {
                            LivePulseDot()
                            Text("ON THE FLOOR NOW")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .tracking(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .overlay(Capsule().strokeBorder(Theme.success.opacity(0.55), lineWidth: 0.6))
                        .padding(12)
                    }

                    if woman.artTier > .freshCanvas {
                        VStack { Spacer(); HStack { Spacer(); ArtTierBadge(tier: woman.artTier, compact: true) } }
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
                            if woman.verified { VerifiedBadge(size: 18) }
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
                        .accessibilityLabel("Bid on \(woman.name)")
                    }
                }
                .padding(16)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(woman.name), \(woman.age), \(woman.location)\(woman.verified ? ", verified" : "")\(woman.startingBid.map { ", starting bid \(Money.full($0))" } ?? ", open bidding")")
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
