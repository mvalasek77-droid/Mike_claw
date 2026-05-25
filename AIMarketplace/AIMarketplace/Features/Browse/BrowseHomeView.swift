import SwiftUI

/// The Netflix / Apple TV-style consumption home: a cinematic hero followed by
/// curated rows including the Top 10 and Trending feeds.
struct BrowseHomeView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @State private var selected: MediaItem?
    @State private var filter: MediaType?
    @State private var showSearch = false

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

                    if let filter {
                        MediaRow(title: filter.plural,
                                 subtitle: "Sorted by AI Editor score",
                                 items: store.items(of: filter)) { selected = $0 }
                    } else {
                        RankedRow(title: "Top 10 Today", items: store.topTen) { selected = $0 }
                        MediaRow(title: "Trending Now", subtitle: "Climbing the charts",
                                 items: store.trending) { selected = $0 }
                        AISpotlightRow()
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
    }

    private var searchButton: some View {
        HStack {
            Spacer()
            Button { Haptics.tap(); showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.black.opacity(0.4)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            }
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var heroItem: MediaItem? {
        if let filter { return store.items(of: filter).first }
        return store.featured
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
                    Chip(text: item.type.title, systemImage: item.type.icon, color: item.type.accent)
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
