import SwiftUI

/// The title page: artwork, metadata, the AI disclosure, the commercial-score
/// rationale, and the buy / consume actions.
struct MediaDetailView: View {
    let item: MediaItem
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var moderation: ModerationStore
    @Environment(\.dismiss) private var dismiss

    @State private var showPlayer = false
    @State private var previewMode = false
    @State private var showInsufficientFunds = false
    @State private var showTopUp = false
    @State private var showWriteReview = false
    @State private var showReportSheet = false

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
                    reviewsBlock
                }
                .padding(.bottom, 40)
            }
            .background(AppBackground().ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showReportSheet = true
                        } label: {
                            Label("Report this title", systemImage: "flag")
                        }
                        if moderation.isBlocked(item.creator) {
                            Button {
                                moderation.unblock(item.creator)
                            } label: {
                                Label("Unblock \(item.creator)", systemImage: "hand.raised.slash")
                            }
                        } else {
                            Button(role: .destructive) {
                                moderation.block(item.creator)
                            } label: {
                                Label("Block creator", systemImage: "hand.raised")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityLabel("More")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(item: item, preview: previewMode)
        }
        .sheet(isPresented: $showTopUp) { TopUpView() }
        .sheet(isPresented: $showWriteReview) { WriteReviewView(item: item) }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(item: item)
                .environmentObject(store)
                .environmentObject(moderation)
        }
        .alert("Not enough balance", isPresented: $showInsufficientFunds) {
            Button("Top Up") { showTopUp = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Add wallet credit to buy this title.")
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

    /// Experimental / niche layer tag (commercial = default, no tag).
    private var layerTag: (String, String)? {
        switch ContentFoundry.layer(forGenre: item.genre) {
        case .experimental: return ("Experimental", "wand.and.stars")
        case .niche: return ("Niche", "scope")
        case .commercial: return nil
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("by \(item.creator)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            if store.isScoutFind(item) {
                Chip(text: "Scout Pick", systemImage: "binoculars.fill", color: Theme.accent, filled: true)
            } else if item.isEditorOriginal {
                Chip(text: "AI Editor Original", systemImage: "sparkles", color: Theme.kdp, filled: true)
            }
            if store.reviewCount(for: item.id) > 0 {
                HStack(spacing: 6) {
                    StarRow(rating: store.averageRating(for: item.id), size: 13)
                    Text(String(format: "%.1f", store.averageRating(for: item.id)))
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("· \(store.reviewCount(for: item.id)) review\(store.reviewCount(for: item.id) == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
            }
            HStack(spacing: 8) {
                if let tag = layerTag {
                    Chip(text: tag.0, systemImage: tag.1, color: Theme.accentSoft, filled: true)
                }
                Chip(text: item.genre, color: item.type.accent)
                Chip(text: "\(item.releaseYear)", color: .white)
                Chip(text: item.maturity, color: .white)
                Chip(text: item.lengthLabel, color: .white)
            }
        }
        .screenPadding()
    }

    @ViewBuilder private var priceNote: some View {
        let delta = store.priceDeltaPercent(for: item)
        if delta != 0 {
            HStack(spacing: 6) {
                Text(item.priceLabel).strikethrough().foregroundStyle(Theme.inkFaint)
                Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(delta > 0 ? Theme.warning : Theme.success)
                Text(delta > 0 ? "In demand · +\(delta)%" : "On sale · \(delta)%")
                    .foregroundStyle(delta > 0 ? Theme.warning : Theme.success)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }

    private var actionBlock: some View {
        VStack(spacing: 10) {
            if store.isComingSoon(item) {
                comingSoonCard
            } else if owned {
                PrimaryButton(title: "\(item.type.verb) now", systemImage: "play.fill", style: .light) {
                    previewMode = false; showPlayer = true
                }
                if item.type == .movie { Text("Full film — downloaded to your Library.").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint) }
            } else {
                PrimaryButton(title: String(format: "Buy · $%.2f", store.effectivePrice(for: item)), systemImage: "cart.fill") {
                    if !store.purchase(item) { showInsufficientFunds = true }
                }
                priceNote
                PrimaryButton(title: previewLabel, systemImage: "eye.fill", style: .ghost) {
                    previewMode = true; showPlayer = true
                }
                Text("Buys with wallet credit, which you top up through the App Store. Grants a personal licence to \(item.type.verb.lowercased()) this title in-app.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
                    .multilineTextAlignment(.center)
            }
            if item.type == .movie && !store.isComingSoon(item) { filmPolicyCard }
            if item.type == .movie && !item.screenplayScenes.isEmpty { scoutFilmProgressCard }
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

    private var previewLabel: String {
        switch item.type {
        case .novel: return "Read a sample"
        case .movie: return "Watch 30 min free"
        case .music: return "Preview"
        }
    }

    private var comingSoonCard: some View {
        GlassCard(tint: Theme.kdp) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Premiering soon", systemImage: "sparkles").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.kdp)
                Text("The Scout is putting the finishing touches on this \(item.type.title.lowercased()). It'll unlock automatically the moment it's ready to premiere.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                ProgressView(value: Double(item.commercialScore), total: 85).tint(Theme.kdp)
                Text("Final polish in progress").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private var filmPolicyCard: some View {
        GlassCard(title: "How this film works", icon: "film.stack", tint: item.type.accent) {
            VStack(alignment: .leading, spacing: 6) {
                policyRow("play.circle", "Watch the first 30 minutes free. Films play in 2–5 minute scenes — start any time, pause any time.")
                policyRow("cart", "Buy once to unlock every remaining scene. No per-scene fees.")
                policyRow("plus.circle", "Films grow over time. The Scout adds new scenes as the film develops — buying now means every future scene is yours too, no extra charge.")
                policyRow("arrow.down.circle", "When the film is complete, the full cut downloads to your Library to keep.")
            }
        }
    }

    /// Visible only for Scout-built films that are growing scene-by-scene.
    /// Tells the buyer exactly what they get today and what's still queued.
    private var scoutFilmProgressCard: some View {
        let scenes = item.screenplayScenes.count
        let target = item.targetMinutes
        let runtime = item.totalSceneMinutes
        let progress = target > 0 ? min(1.0, Double(runtime) / Double(target)) : 1.0
        return GlassCard(title: item.isFilmComplete ? "Full film available" : "Film in progress",
                          icon: "hourglass", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.isFilmComplete
                     ? "\(scenes) scenes · \(runtime) min total."
                     : "\(scenes) of an estimated \(max(scenes + 1, target / 3)) scenes published · \(runtime) of \(target) min so far.")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                if !item.isFilmComplete {
                    ProgressView(value: progress).tint(Theme.accent)
                    Text("The Scout adds a new 2–5 min scene each cycle. Buying now locks in your access to every scene as it ships.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    private func policyRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(item.type.accent).frame(width: 18)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 0)
        }
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
            metaCell("Type", item.categoryLabel, item.type.icon)
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

    private var reviewsBlock: some View {
        // Hide reviews from creators this device has blocked.
        let reviews = store.reviewList(for: item.id).filter { !moderation.isBlocked($0.author) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Ratings & reviews",
                              subtitle: reviews.isEmpty ? "Be the first to review" : nil)
                Spacer()
                if owned {
                    Button(store.hasReviewed(item.id) ? "Edit" : "Write") { showWriteReview = true }
                        .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent)
                }
            }
            if !reviews.isEmpty {
                HStack(spacing: 12) {
                    Text(String(format: "%.1f", store.averageRating(for: item.id)))
                        .font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    VStack(alignment: .leading, spacing: 3) {
                        StarRow(rating: store.averageRating(for: item.id), size: 15)
                        Text("\(reviews.count) review\(reviews.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                }
                ForEach(reviews.prefix(6)) { review in reviewRow(review) }
            } else if !owned {
                Text("Buy this title to rate and review it.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
        }
        .screenPadding()
    }

    private func reviewRow(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(review.author).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                StarRow(rating: Double(review.rating), size: 10)
                Spacer()
                Text(review.date, style: .date).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkFaint)
            }
            if !review.text.isEmpty {
                Text(review.text).font(.system(size: 13, weight: .regular)).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
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