import SwiftUI

/// The viewer's purchased titles plus their saved "My List".
struct LibraryView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @State private var selected: MediaItem?
    @State private var showRequest = false

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

                    requestBanner

                    if !store.requests.isEmpty { commissionsSection }

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
        .sheet(isPresented: $showRequest) { RequestContentView() }
    }

    private var requestBanner: some View {
        Button { showRequest = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 22)).foregroundStyle(Theme.kdp)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Request content").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("Describe what you want, name your price — an AI will make it")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.cornerL).fill(Theme.kdp.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerL).strokeBorder(Theme.kdp.opacity(0.3), lineWidth: 0.8))
            .screenPadding()
        }
        .buttonStyle(.plain)
    }

    private var commissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "My commissions").screenPadding()
            VStack(spacing: 10) {
                ForEach(store.requests) { request in commissionRow(request) }
            }
            .screenPadding()
        }
    }

    private func commissionRow(_ request: ContentRequest) -> some View {
        let delivered = request.deliveredItemID.flatMap { store.item(withID: $0) }
        return Button {
            if let delivered { selected = delivered }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: request.type.icon).font(.system(size: 15)).foregroundStyle(request.type.accent)
                    .frame(width: 38, height: 38).background(Circle().fill(request.type.accent.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.headline).font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink).lineLimit(1)
                    Text(statusText(request)).font(.system(size: 11, weight: .medium)).foregroundStyle(statusColor(request))
                }
                Spacer()
                Text(String(format: "$%.2f", request.budgetUSD))
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft)
                if delivered != nil {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.inkFaint)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .disabled(delivered == nil)
    }

    private func statusText(_ r: ContentRequest) -> String {
        switch r.status {
        case .open: return "Finding an AI…"
        case .accepted: return "Accepted by \(r.acceptedBy ?? "an AI") — producing"
        case .delivered: return "Delivered by \(r.acceptedBy ?? "an AI") · tap to open"
        case .unmatched: return "No AI accepted — raise the budget"
        }
    }

    private func statusColor(_ r: ContentRequest) -> Color {
        switch r.status {
        case .open, .accepted: return Theme.accent
        case .delivered: return Theme.success
        case .unmatched: return Theme.warning
        }
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
