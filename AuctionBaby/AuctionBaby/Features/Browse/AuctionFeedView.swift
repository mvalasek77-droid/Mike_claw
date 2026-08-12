import SwiftUI
import UIKit

/// The bidder's home: a Hinge-style vertical feed of women on the floor. Each
/// card is a tappable lot. Copycats render EXACTLY like real profiles here —
/// the house rule is no pre-bid labelling; the reveal fires after the bid.
struct AuctionFeedView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var profileSync: ProfileService
    @EnvironmentObject private var auth: AuthService
    @State private var bidTarget: Profile?
    @State private var showFilters = false
    @State private var showActivity = false
    @State private var showLotOfDay = false
    @State private var showGavelStore = false
    /// Explicit nav path so a Floor card can push its detail from a body tap
    /// while the inline Bid button keeps its own tap (see the lots ForEach).
    @State private var lotPath: [Profile] = []

    private var lots: [Profile] { store.filteredFloor.filter { $0.id != store.lotOfTheDay?.id } }

    var body: some View {
        NavigationStack(path: $lotPath) {
            ScrollView {
                LazyVStack(spacing: 18) {
                    header
                    if store.isRemoteFloor {
                        realFloorChip
                    }
                    LiveTicker()
                    DailyClaimCard()
                    if let star = store.lotOfTheDay {
                        NavigationLink(value: star) { LotOfTheDayBanner(woman: star) }
                            .buttonStyle(ScaleButtonStyle(scale: 0.98))
                            .riseIn(0.05)
                    }
                    if lots.isEmpty && store.lotOfTheDay == nil {
                        EmptyStateView(icon: "line.3.horizontal.decrease.circle",
                                       title: "No lots match",
                                       message: "Your filters are hiding everyone. Loosen them to see more of the floor.")
                    }
                    ForEach(Array(lots.enumerated()), id: \.element.id) { i, woman in
                        // Body tap → detail; the inline Bid button stays its own
                        // control. Nesting a Button inside a NavigationLink let
                        // the link swallow the Bid tap on iOS 18 (users landed on
                        // the detail instead of the bid sheet). A container
                        // onTapGesture doesn't steal the Button's own hits.
                        FloorCard(woman: woman,
                                  onOpen: { lotPath.append(woman) },
                                  onBid: { bidTarget = woman })
                            // FloorCards are tall — only the first ~3 are ever in
                            // the initial viewport. Rows past that render statically
                            // so the entrance animation never fires mid-scroll.
                            .riseIn(Double(i) * 0.05, active: i < 3)
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
                                .font(.dynamicScaled(17, weight: .semibold, relativeTo: .body))
                            if store.filters.activeCount > 0 {
                                Text("\(store.filters.activeCount)")
                                    .font(.dynamicScaled(9, weight: .heavy, design: .rounded, relativeTo: .caption2))
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
            // Batch T — when the filters sheet closes, refetch the floor so
            // the server sees the new age/verifiedOnly bounds. A local
            // Equatable check on `filters` here would fire on every slider
            // tick; dismissal is the natural commit point.
            .onChange(of: showFilters) { _, isOpen in
                if !isOpen {
                    Task { await store.refreshRemoteFloor(profileSync: profileSync) }
                }
            }
            .sheet(isPresented: $showActivity) { ActivityView() }
            .sheet(isPresented: $showGavelStore) { GavelStoreView() }
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
            // Slice 4b1a — fetch the real signed-in floor. Demo Mode + local-
            // only sessions no-op inside refreshRemoteFloor.
            .task(id: auth.serverUserId) {
                await store.refreshRemoteFloor(profileSync: profileSync)
            }
            .refreshable {
                await store.refreshRemoteFloor(profileSync: profileSync)
            }
        }
    }

    /// The "you're seeing real bidders" chip. Renders only when `isRemoteFloor`
    /// is true (signed-in + at least one other real user has joined). A
    /// signed-in user on a fresh platform still sees the sim as bootstrap;
    /// this chip is the visual signal that the switch has flipped.
    private var realFloorChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.dynamicScaled(10, weight: .bold, relativeTo: .caption2))
            Text("Real people on the floor")
                .font(.dynamicScaled(11, weight: .heavy, design: .rounded, relativeTo: .caption2))
                .tracking(0.4)
        }
        .foregroundStyle(Theme.verify)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.verify.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.verify.opacity(0.30), lineWidth: 0.8))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tonight's lots")
                    .font(.dynamicScaled(14, weight: .bold, design: .rounded, relativeTo: .footnote))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                if store.isBoosted, let until = store.boostUntil {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.dynamicScaled(10, weight: .bold, relativeTo: .caption2))
                        Text(timerInterval: Date.now...max(until, Date.now.addingTimeInterval(1)), countsDown: true)
                            .font(.dynamicScaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Theme.rose)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.rose.opacity(0.16)))
                }
                Button { showGavelStore = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "hammer.fill").font(.dynamicScaled(11, weight: .bold, relativeTo: .caption2))
                        Text(Tally.compact(store.wallet))
                            .font(.dynamicScaled(13, weight: .heavy, design: .rounded, relativeTo: .footnote))
                        Image(systemName: "plus.circle.fill").font(.dynamicScaled(11, weight: .bold, relativeTo: .caption2))
                            .opacity(0.75)
                    }
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.gold.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gavels: \(store.wallet). Tap to buy more.")
            }
            Text("Bid what a date is worth. She unlocks your photo when she accepts.")
                .font(.dynamicScaled(12, weight: .medium, relativeTo: .caption1))
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
                Image(systemName: "hammer.fill").font(.dynamicScaled(11, weight: .bold, relativeTo: .caption2))
                Text("LOT OF THE DAY").font(.dynamicScaled(11, weight: .heavy, design: .rounded, relativeTo: .caption2)).tracking(1.5)
                Spacer()
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.goldGradient)

            ZStack(alignment: .bottomLeading) {
                AvatarView(name: woman.name, hue: woman.hue, photoName: woman.photoName,
                           remotePhotoURL: woman.remotePhotoURLs.first, corner: 0)
                    .frame(height: 240)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                    .frame(height: 240).allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(woman.name).font(.dynamicScaled(26, weight: .heavy, design: .serif, relativeTo: .title1))
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
            guard !Motion.prefersReducedMotion else { return }
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
                            .font(.dynamicScaled(13, weight: .bold, relativeTo: .footnote))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Label("TONIGHT'S LOT", systemImage: "hammer.fill")
                        .font(.dynamicScaled(12, weight: .heavy, design: .rounded, relativeTo: .caption1)).tracking(2)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.goldGradient))
                    Text("Curated for tonight only")
                        .font(.dynamicScaled(12, weight: .semibold, design: .rounded, relativeTo: .caption1))
                        .foregroundStyle(Theme.inkFaint)
                }

                ZStack(alignment: .bottomLeading) {
                    AvatarView(name: woman.name, hue: woman.hue,
                               photoName: woman.photoName, photoData: woman.photoData,
                               remotePhotoURL: woman.remotePhotoURLs.first,
                               corner: Theme.cornerXL)
                        .frame(height: 380)
                    LinearGradient(colors: [.clear, .black.opacity(0.85)],
                                   startPoint: .center, endPoint: .bottom)
                        .frame(height: 380).allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(woman.name)
                                .font(.dynamicScaled(32, weight: .heavy, design: .serif, relativeTo: .largeTitle))
                            if woman.verified { VerifiedBadge(size: 20) }
                            Text("\(woman.age)")
                                .font(.dynamicScaled(22, weight: .medium, design: .serif, relativeTo: .title2))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .foregroundStyle(Theme.ink)
                        HStack(spacing: 8) {
                            ArtTierBadge(tier: woman.artTier, compact: true)
                            Chip(text: "Showcase \(woman.showcaseCredit)",
                                 systemImage: "rosette", color: Theme.rose)
                        }
                        Text(woman.location)
                            .font(.dynamicScaled(13, weight: .medium, relativeTo: .footnote))
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
                        .font(.dynamicScaled(13, weight: .semibold, design: .rounded, relativeTo: .footnote))
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
                guard !Motion.prefersReducedMotion else { return }
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
    /// Tapping the photo region opens the detail. Kept separate from `onBid`
    /// so the two hit areas never overlap — a navigation gesture covering the
    /// whole card swallows the inline Bid button's tap (iOS 18).
    var onOpen: () -> Void = {}
    var onBid: () -> Void

    var body: some View {
        GlassSurface(corner: Theme.cornerXL) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    AvatarView(name: woman.name, hue: woman.hue, photoName: woman.photoName,
                               remotePhotoURL: woman.remotePhotoURLs.first,
                               corner: Theme.cornerXL)
                        .frame(height: 360)

                    if woman.isOnTheFloorNow {
                        HStack(spacing: 5) {
                            LivePulseDot()
                            Text("ON THE FLOOR NOW")
                                .font(.dynamicScaled(10, weight: .heavy, design: .rounded, relativeTo: .caption2))
                                .tracking(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .overlay(Capsule().strokeBorder(Theme.success.opacity(0.55), lineWidth: 0.6))
                        .padding(12)
                    }

                    if woman.isSpotlightBoosted {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.dynamicScaled(10, weight: .bold, relativeTo: .caption2))
                            Text("SPOTLIGHT")
                                .font(.dynamicScaled(9, weight: .heavy, design: .rounded, relativeTo: .caption2))
                                .tracking(1)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.gold))
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
                                .font(.dynamicScaled(26, weight: .heavy, design: .serif, relativeTo: .title1))
                            if woman.verified { VerifiedBadge(size: 18) }
                            Text("\(woman.age)")
                                .font(.dynamicScaled(20, weight: .medium, design: .serif, relativeTo: .title3))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .foregroundStyle(Theme.ink)
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse").font(.dynamicScaled(11, relativeTo: .caption2))
                            Text(woman.location).font(.dynamicScaled(12, weight: .medium, relativeTo: .caption1))
                        }
                        .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: 360, alignment: .bottomLeading)
                }
                // Navigation lives ONLY on the photo — a separate subtree from
                // the Bid button below, so the two never contend for a tap.
                // The photo is ALSO the combined VoiceOver element (the profile
                // summary); the Bid button stays a separate a11y element so both
                // VoiceOver and XCUITest can target it precisely. Combining the
                // whole card instead made the Bid tap land on the photo centre.
                .contentShape(Rectangle())
                .onTapGesture { onOpen() }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(woman.name), \(woman.age), \(woman.location)\(woman.verified ? ", verified" : "")\(woman.startingBid.map { ", starting bid \(Money.full($0))" } ?? ", open bidding")")

                VStack(alignment: .leading, spacing: 12) {
                    if !woman.bio.isEmpty {
                        Text(woman.bio)
                            .font(.dynamicScaled(14, weight: .medium, relativeTo: .footnote))
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
                            .font(.dynamicScaled(15, weight: .heavy, design: .rounded, relativeTo: .subheadline))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(Capsule().fill(Theme.goldGradient))
                            .depth(40, strong: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Bid on \(woman.name)")
                        .accessibilityIdentifier("floor_bid")
                    }
                }
                .padding(16)
            }
        }
        // Card-level combine removed: it merged the Bid button into one element,
        // so a tap on floor_bid hit the combined frame's centre (the photo) and
        // navigated instead of bidding. The photo carries the summary label now.
    }
}

/// Compact floor / value readout shown on each card.
struct FloorStat: View {
    let woman: Profile
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let bid = woman.startingBid {
                Text("Starting bid").font(.dynamicScaled(10, weight: .bold, design: .rounded, relativeTo: .caption2))
                    .foregroundStyle(Theme.inkFaint)
                Text(Money.full(bid)).font(.dynamicScaled(18, weight: .heavy, design: .rounded, relativeTo: .body))
                    .foregroundStyle(Theme.gold)
            } else {
                Text("No floor").font(.dynamicScaled(10, weight: .bold, design: .rounded, relativeTo: .caption2))
                    .foregroundStyle(Theme.inkFaint)
                Text("Open bidding").font(.dynamicScaled(15, weight: .heavy, design: .rounded, relativeTo: .subheadline))
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
                .font(.dynamicScaled(12, weight: .semibold, relativeTo: .caption1))
                .foregroundStyle(Theme.inkSoft)
            Text(prompt.answer)
                .font(.dynamicScaled(17, weight: .bold, design: .serif, relativeTo: .body))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerM).strokeBorder(Theme.hairline, lineWidth: 0.6))
    }
}
