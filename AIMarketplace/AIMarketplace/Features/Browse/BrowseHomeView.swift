import SwiftUI

/// The Netflix / Apple TV-style consumption home: a cinematic hero followed by
/// curated rows including the Top 10 and Trending feeds.
struct BrowseHomeView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var moderation: ModerationStore
    @State private var selected: MediaItem?
    @State private var filter: MediaType?
    @State private var layerFilter: ContentFoundry.ScoutLayer?
    @State private var showSearch = false
    @State private var showNotifications = false
    /// The inaugural-roundtable launch sheet — shown once per device on the
    /// first launch where the audio file is actually bundled.
    @State private var launchItem: MediaItem?

    private var rows: [MediaType] { MediaType.allCases }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    if let hero = heroItem {
                        HeroBanner(item: hero,
                                   onPlay: { selected = hero },
                                   onInfo: { selected = hero })
                    }

                    filterBar
                    layerBar

                    if filter != nil || layerFilter != nil {
                        MediaRow(title: filterTitle,
                                 subtitle: "Sorted by AI Editor score",
                                 items: filteredItems) { selected = $0 }
                    } else {
                        pendingProposalsRail
                        RankedRow(title: "Top 10 Today", items: store.topTen) { selected = $0 }
                        MediaRow(title: "Trending Now", subtitle: "Climbing the charts",
                                 items: store.trending) { selected = $0 }
                        MediaRow(title: "Scout Picks",
                                 subtitle: "Sourced by The Scout at the top of the range",
                                 items: store.scoutPicks) { selected = $0 }
                        AISpotlightRow()
                        MediaRow(title: "AI Editor Originals",
                                 subtitle: "Produced by the Editor to fill the catalogue",
                                 items: store.editorOriginals) { selected = $0 }
                        MediaRow(title: "Just Published", subtitle: "Fresh off the AI Editor",
                                 items: store.newReleases) { selected = $0 }
                        ForEach(rows) { type in
                            MediaRow(title: "AI \(type.plural)",
                                     items: store.items(of: type)) { selected = $0 }
                        }
                    }
                }
                .padding(.bottom, 96)
            }

            searchButton
        }
        .sheet(item: $selected) { item in
            MediaDetailView(item: item)
        }
        .sheet(isPresented: $showSearch) { SearchView() }
        .sheet(isPresented: $showNotifications) { NotificationsView() }
        .sheet(item: $launchItem) { item in
            InauguralLaunchSheet(item: item, onPlay: { selected = item })
        }
        .task {
            // Show the inaugural launch sheet once on first start after the
            // MP3 has actually been bundled. Triggers off the catalog the
            // first time this view appears in a session.
            if launchItem == nil {
                launchItem = InauguralLaunchSheet.itemIfReady(in: store.catalog)
            }
        }
    }

    private var searchButton: some View {
        HStack(spacing: 10) {
            Spacer()
            circleButton("bell.fill", badge: store.unreadNotificationCount) {
                showNotifications = true
            }
            .accessibilityLabel("Notifications")
            circleButton("magnifyingglass", badge: 0) { showSearch = true }
                .accessibilityLabel("Search")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func circleButton(_ icon: String, badge: Int, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Circle().fill(.black.opacity(0.4)))
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(min(badge, 9))\(badge > 9 ? "+" : "")")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Circle().fill(Theme.kdp))
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var heroItem: MediaItem? {
        if filter != nil || layerFilter != nil { return filteredItems.first }
        if let featured = store.featured, !moderation.isBlocked(featured.creator) {
            return featured
        }
        return filteredItems.first
    }

    /// Horizontal rail of Scout's pending proposals — placeholder cards
    /// telling everyone what's in the queue waiting on admin authorization.
    /// Visible on the home view so the production pipeline is transparent,
    /// not hidden inside the Scout tab.
    @ViewBuilder
    private var pendingProposalsRail: some View {
        let pending = store.pendingScoutProposals.prefix(8)
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 11)).foregroundStyle(Theme.warning)
                    Text("Awaiting authorization")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("· \(pending.count) in Scout's deck")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                    Spacer()
                }
                .padding(.horizontal, 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(pending)) { p in
                            pendingProposalCard(p)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
        }
    }

    private func pendingProposalCard(_ p: ScoutProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: p.type.icon)
                    .font(.system(size: 11)).foregroundStyle(p.type.accent)
                Text(p.type.title.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
                Spacer()
                Text("PENDING")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().stroke(Theme.warning, lineWidth: 1))
            }
            Text(p.title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(p.genre)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(p.type.accent)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "scalemass")
                    .font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
                Text(p.estimatedUSD > 0
                     ? "$\(String(format: "%.2f", p.estimatedUSD))"
                     : "Free")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text("· \(p.estimatedTokens) tk")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(12)
        .frame(width: 170, height: 170, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.warning.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private func matches(_ item: MediaItem) -> Bool {
        guard !moderation.isBlocked(item.creator) else { return false }
        return (filter == nil || item.type == filter)
            && (layerFilter == nil || ContentFoundry.layer(forGenre: item.genre) == layerFilter)
    }

    private var filteredItems: [MediaItem] {
        store.catalog.filter(matches).sorted { $0.commercialScore > $1.commercialScore }
    }

    private var filterTitle: String {
        let layer = layerFilter.map { $0.rawValue.capitalized + " " } ?? ""
        return layer + (filter?.plural ?? "Titles")
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(nil, "All")
                ForEach(MediaType.allCases) { type in
                    pill(type, type.plural)
                }
            }
            .screenPadding()
        }
    }

    private var layerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                layerPill(nil, "Every layer")
                ForEach(ContentFoundry.ScoutLayer.allCases, id: \.self) { layer in
                    layerPill(layer, layer.rawValue.capitalized)
                }
            }
            .screenPadding()
        }
    }

    private func layerPill(_ layer: ContentFoundry.ScoutLayer?, _ label: String) -> some View {
        let active = layerFilter == layer
        return Button {
            Motion.run(Motion.snap) { layerFilter = layer }
            Haptics.selection()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(active ? .black : Theme.accentSoft)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(active ? Theme.accent : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func pill(_ type: MediaType?, _ label: String) -> some View {
        let active = filter == type
        return Button {
            Motion.run(Motion.snap) { filter = type }
            Haptics.selection()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(active ? .black : Theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(active ? Color.white : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }
}

/// Full-width cinematic banner for the marquee title.
struct HeroBanner: View {
    let item: MediaItem
    var onPlay: () -> Void
    var onInfo: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            PosterArt(item: item, showsTitle: false)
                .frame(height: 460)
                .overlay(
                    LinearGradient(colors: [.clear, .clear, Theme.bg],
                                   startPoint: .top, endPoint: .bottom)
                )

            VStack(spacing: 12) {
                Text(item.title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(radius: 8)

                HStack(spacing: 8) {
                    Chip(text: item.categoryLabel, systemImage: item.type.icon, color: item.type.accent)
                    Chip(text: item.genre, color: .white)
                    ScoreBadge(score: item.commercialScore)
                }

                HStack(spacing: 10) {
                    PrimaryButton(title: item.type.verb, systemImage: "play.fill", style: .light) { onPlay() }
                    PrimaryButton(title: "More Info", systemImage: "info.circle", style: .ghost) { onInfo() }
                }
                .padding(.horizontal, 30)
            }
            .padding(.bottom, 8)
        }
    }
}
