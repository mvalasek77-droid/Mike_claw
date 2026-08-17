import SwiftUI

/// A single listing: photo, price, description, and a composer that sends an
/// in-app message to the seller (no contact info is ever exposed).
struct ListingDetailView: View {
    @State private var model: ListingDetailViewModel
    var onOpenMessages: (() -> Void)? = nil

    init(listing: Listing, service: MarketplaceService, onOpenMessages: (() -> Void)? = nil) {
        _model = State(initialValue: ListingDetailViewModel(listing: listing, service: service))
        self.onOpenMessages = onOpenMessages
    }

    private var isMine: Bool { model.listing.seller.id == Session.me.id }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                    photo
                    header
                    if !model.listing.description.isEmpty {
                        Text(model.listing.description)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(Tokens.Color.textPrimary)
                    }
                    sellerRow
                }
                .padding(Tokens.Spacing.lg)
            }
            if !isMine {
                composer
            }
        }
        .navigationTitle(model.listing.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var photo: some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous)
            .fill(Tokens.Color.accent.opacity(0.18))
            .frame(height: 200)
            .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(Tokens.Color.textSecondary))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.listing.category.label)
                    .font(Tokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(Tokens.Color.textSecondary)
                if model.listing.isSold {
                    Text("Sold")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Text(model.listing.price == 0 ? "Free" : model.listing.price.formatted(.currency(code: "USD")))
                .font(Tokens.Typography.headline)
                .foregroundStyle(Tokens.Color.textPrimary)
        }
    }

    private var sellerRow: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            UserAvatar(user: model.listing.seller, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.listing.seller.displayName)
                    .font(Tokens.Typography.caption.weight(.semibold))
                Text("Seller")
                    .font(.caption2)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            Spacer()
        }
        .padding(Tokens.Spacing.md)
        .liquidGlass()
    }

    private var composer: some View {
        VStack(spacing: Tokens.Spacing.sm) {
            if case .failed(let message) = model.sendState {
                Text(message)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.red)
            }
            if model.sendState == .sent {
                HStack {
                    Label("Message sent to the seller", systemImage: "checkmark.circle.fill")
                        .font(Tokens.Typography.caption.weight(.semibold))
                        .foregroundStyle(Tokens.Color.accent)
                    Spacer()
                    if let onOpenMessages {
                        Button("Go to Messages") { onOpenMessages() }
                            .font(Tokens.Typography.caption.weight(.bold))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }
            HStack(spacing: Tokens.Spacing.sm) {
                TextField("Message the seller…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Tokens.Spacing.md)
                    .padding(.vertical, Tokens.Spacing.sm)
                    .liquidGlass(radius: Tokens.Radius.pill)

                Button {
                    Task { await model.send() }
                } label: {
                    if model.sendState == .sending {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(!model.canSend)
                .accessibilityLabel("Send message")
            }
        }
        .padding(Tokens.Spacing.lg)
    }
}
