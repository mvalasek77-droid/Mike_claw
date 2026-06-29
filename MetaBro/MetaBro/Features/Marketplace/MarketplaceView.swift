import SwiftUI

/// Buy/sell/trade listings (the Bro-ket): browse by category, tap into a
/// listing to message the seller in-app. The + button posts a new listing.
struct MarketplaceView: View {
    private let container: AppContainer
    @State private var model: MarketplaceViewModel
    @State private var showingCreate = false
    @Environment(\.dismiss) private var dismiss

    init(container: AppContainer) {
        self.container = container
        _model = State(initialValue: MarketplaceViewModel(service: container.marketplaceService))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Bro-ket")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Listing.self) { listing in
                    ListingDetailView(listing: listing, service: container.marketplaceService)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingCreate = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Post a listing")
                    }
                }
                .sheet(isPresented: $showingCreate) {
                    CreateListingView(service: container.marketplaceService) { listing in
                        model.created(listing)
                    }
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("No listings yet", systemImage: "cart",
                                   description: Text("Post something with the + button."))
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let listings):
            ScrollView {
                VStack(spacing: Tokens.Spacing.lg) {
                    categoryFilterBar
                    let visible = model.visible(from: listings)
                    if visible.isEmpty {
                        ContentUnavailableView("Nothing in this category", systemImage: "cart")
                            .frame(minHeight: 200)
                    } else {
                        LazyVStack(spacing: Tokens.Spacing.md) {
                            ForEach(visible) { listing in
                                NavigationLink(value: listing) {
                                    ListingRow(listing: listing)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .animation(Tokens.Motion.gentle, value: visible)
                    }
                }
                .padding(Tokens.Spacing.lg)
            }
            .refreshable { await model.load() }
        }
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Spacing.sm) {
                FilterChip(label: "All", isSelected: model.categoryFilter == nil) {
                    model.categoryFilter = nil
                }
                ForEach(ListingCategory.allCases, id: \.self) { category in
                    FilterChip(label: category.label, isSelected: model.categoryFilter == category) {
                        model.categoryFilter = category
                    }
                }
            }
        }
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(Tokens.Typography.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : Tokens.Color.textSecondary)
                .padding(.horizontal, Tokens.Spacing.md)
                .padding(.vertical, Tokens.Spacing.sm)
                .background {
                    Capsule().fill(isSelected
                                   ? AnyShapeStyle(Tokens.Color.accent)
                                   : AnyShapeStyle(.ultraThinMaterial))
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ListingRow: View {
    let listing: Listing

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous)
                .fill(Tokens.Color.accent.opacity(0.18))
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "photo").foregroundStyle(Tokens.Color.textSecondary))

            VStack(alignment: .leading, spacing: 2) {
                Text(listing.title)
                    .font(Tokens.Typography.headline)
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(1)
                Text(listing.category.label)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(listing.price == 0 ? "Free" : listing.price.formatted(.currency(code: "USD")))
                    .font(Tokens.Typography.headline)
                    .foregroundStyle(Tokens.Color.textPrimary)
                if listing.isSold {
                    Text("Sold")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Tokens.Color.textSecondary)
                }
            }
        }
        .padding(Tokens.Spacing.md)
        .liquidGlass()
        .opacity(listing.isSold ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}
