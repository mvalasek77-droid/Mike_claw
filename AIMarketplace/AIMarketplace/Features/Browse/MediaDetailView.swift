import SwiftUI

/// The title page: artwork, metadata, the AI disclosure, the commercial-score
/// rationale, and the buy / consume actions.
struct MediaDetailView: View {
    let item: MediaItem
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var showPlayer = false
    @State private var showInsufficientFunds = false

    private var owned: Bool { store.owns(item) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    headerArt
                    titleBlock
                    actionBlock
                    synopsisBlock
                    aiDisclosureBlock
                    scoreBlock
                    metaGrid
                }
                .padding(.bottom, 40)
            }
            .background(AppBackground().ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(item: item)
        }
        .alert("Not enough balance", isPresented: $showInsufficientFunds) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Top up your wallet from the You tab to buy this title.")
        }
    }

    private var headerArt: some View {
        PosterArt(item: item, showsTitle: false)
            .frame(height: 320)
            .overlay(
                LinearGradient(colors: [.clear, Theme.bg.opacity(0.9)],
                               startPoint: .center, endPoint: .bottom)
            )
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: item.type.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(item.type.accent)
                    Text(item.title)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(18)
            }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("by \(item.creator)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 8) {
                Chip(text: item.genre, color: item.type.accent)
                Chip(text: "\(item.releaseYear)", color: .white)
                Chip(text: item.maturity, color: .white)
                Chip(text: item.lengthLabel, color: .white)
            }
        }
        .screenPadding()
    }

    private var actionBlock: some View {
        VStack(spacing: 10) {
            if owned {
                PrimaryButton(title: "\(item.type.verb) now", systemImage: "play.fill", style: .light) {
                    showPlayer = true
                }
            } else {
                PrimaryButton(title: "Buy · \(item.priceLabel)", systemImage: "cart.fill") {
                    if !store.purchase(item) { showInsufficientFunds = true }
                }
            }
            HStack(spacing: 10) {
                PrimaryButton(
                    title: store.watchlistIDs.contains(item.id) ? "In My List" : "My List",
                    systemImage: store.watchlistIDs.contains(item.id) ? "checkmark" : "plus",
                    style: .ghost
                ) { store.toggleWatchlist(item) }

                if owned {
                    PrimaryButton(title: "Owned", systemImage: "checkmark.seal.fill", style: .ghost, tint: Theme.success) { }
                        .disabled(true)
                }
            }
        }
        .screenPadding()
    }

    private var synopsisBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Synopsis")
            Text(item.synopsis)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.ink.opacity(0.9))
                .lineSpacing(3)
        }
        .screenPadding()
    }

    private var aiDisclosureBlock: some View {
        GlassCard(title: "Made with AI", icon: "cpu", tint: item.type.accent) {
            VStack(alignment: .leading, spacing: 10) {
                Text("This \(item.type.title.lowercased()) was produced using:")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                FlowChips(items: item.aiTools, color: item.type.accent)
            }
        }
        .screenPadding()
    }

    private var scoreBlock: some View {
        GlassCard(title: "AI Editor Verdict", icon: "checkmark.seal.fill", tint: Theme.success) {
            HStack(alignment: .center, spacing: 16) {
                ScoreRing(score: item.commercialScore, size: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.grade)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.success)
                    Text("Cleared the 85% commercial-quality bar before going on sale.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .screenPadding()
    }

    private var metaGrid: some View {
        HStack(spacing: 10) {
            metaCell("Purchases", "\(item.purchases.formatted())", "cart")
            metaCell("Momentum", "\(item.trending)/100", "flame.fill")
            metaCell("Type", item.type.title, item.type.icon)
        }
        .screenPadding()
    }

    private func metaCell(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(item.type.accent)
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
    }
}

/// Simple wrapping chip layout for AI-tool tags.
struct FlowChips: View {
    let items: [String]
    var color: Color = .white

    var body: some View {
        FlexibleHStack(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { Chip(text: $0, systemImage: "sparkles", color: color) }
        }
    }
}

/// Lightweight wrapping HStack so chips flow onto multiple lines.
struct FlexibleHStack<Content: View>: View {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Uses native layout; falls back gracefully across line widths.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content() }
            FlowLayout(spacing: spacing, lineSpacing: lineSpacing) { content() }
        }
    }
}

/// A minimal flow layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
