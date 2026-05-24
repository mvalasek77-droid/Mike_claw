import SwiftUI

/// The viewer's purchased titles plus their saved "My List".
struct LibraryView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @State private var selected: MediaItem?

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 12)]

    private var watchlist: [MediaItem] {
        store.catalog.filter { store.watchlistIDs.contains($0.id) && !store.owns($0) }
    }

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("My Library")
                        .font(.displayL)
                        .foregroundStyle(Theme.ink)
                        .screenPadding()
                        .padding(.top, 8)

                    if store.library.isEmpty && watchlist.isEmpty {
                        emptyState
                    } else {
                        if !store.library.isEmpty {
                            grid(title: "Purchased · \(store.library.count)", items: store.library)
                        }
                        if !watchlist.isEmpty {
                            grid(title: "My List", items: watchlist)
                        }
                    }
                }
                .padding(.bottom, 96)
            }
        }
        .sheet(item: $selected) { MediaDetailView(item: $0) }
    }

    private func grid(title: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title).screenPadding()
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items) { item in
                    MediaCard(item: item, width: 108) { selected = item }
                }
            }
            .screenPadding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(Theme.inkFaint)
            Text("Your library is empty")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text("Buy a novel, album or film from Home and it will appear here to read, listen, or watch any time.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 80)
    }
}
