import SwiftUI

/// Storefront search — the discovery surface every major media seller leads
/// with. Matches across title, creator, genre, synopsis and the AI tools that
/// made a work. Empty state offers genre shortcuts and trending suggestions.
struct SearchView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var typeFilter: MediaType?
    @State private var selected: MediaItem?
    @FocusState private var focused: Bool

    private var results: [MediaItem] {
        let base = store.search(query)
        guard let typeFilter else { return base }
        return base.filter { $0.type == typeFilter }
    }

    private let grid = [GridItem(.adaptive(minimum: 108), spacing: 12)]

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            VStack(spacing: 14) {
                searchBar
                if !query.trimmed.isEmpty { typeFilterBar }

                ScrollView(showsIndicators: false) {
                    if query.trimmed.isEmpty {
                        suggestions
                    } else if results.isEmpty {
                        emptyResults
                    } else {
                        resultsGrid
                    }
                }
            }
            .padding(.top, 10)
        }
        .sheet(item: $selected) { MediaDetailView(item: $0) }
        .onAppear { focused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSoft)
                TextField("Titles, creators, genres, AI models", text: $query)
                    .focused($focused)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkFaint)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.08)))

            Button("Cancel") { dismiss() }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
        }
        .screenPadding()
    }

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(nil, "All")
                ForEach(MediaType.allCases) { type in pill(type, type.plural) }
            }
            .screenPadding()
        }
    }

    private func pill(_ type: MediaType?, _ label: String) -> some View {
        let active = typeFilter == type
        return Button {
            Haptics.selection()
            typeFilter = type
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(active ? .black : Theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(active ? Color.white : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private var resultsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                .screenPadding()
            LazyVGrid(columns: grid, spacing: 14) {
                ForEach(results) { item in
                    MediaCard(item: item, width: 108) { selected = item }
                }
            }
            .screenPadding()
        }
        .padding(.bottom, 30)
    }

    private var emptyResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 42)).foregroundStyle(Theme.inkFaint)
            Text("No matches for “\(query.trimmed)”")
                .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text("Try a different title, creator, genre or AI model.")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.top, 70).padding(.horizontal, 30)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !store.genres.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Browse by genre").screenPadding()
                    FlexibleHStack(spacing: 8, lineSpacing: 8) {
                        ForEach(store.genres, id: \.self) { genre in
                            Button { query = genre } label: {
                                Chip(text: genre, color: Theme.accent)
                            }.buttonStyle(.plain)
                        }
                    }
                    .screenPadding()
                }
            }
            MediaRow(title: "Trending now", subtitle: "What people are buying",
                     items: store.trending) { selected = $0 }
        }
        .padding(.bottom, 30)
    }
}
