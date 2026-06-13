import SwiftUI

/// Full AI Spotlight: every model that has shipped work, ranked by reach, each
/// a tappable portfolio of what it can do.
struct AISpotlightView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStudio: AIStudio?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                Text("Every model below earns its place by shipping work that cleared the AI Editor. Tap one to see what it can do.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.top, 6)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(store.aiStudios) { studio in
                        StudioCard(studio: studio) { selectedStudio = studio }
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle("AI Spotlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(item: $selectedStudio) { AIStudioDetailView(studio: $0) }
    }
}

/// Home-screen row introducing the AI Spotlight: a horizontally scrolling strip
/// of model portfolios with a "See all" into the full grid. Owns its own
/// presentation so the browse home isn't burdened with extra sheets.
struct AISpotlightRow: View {
    @EnvironmentObject private var store: MarketplaceStore
    @State private var activeSheet: SpotlightSheet?

    enum SpotlightSheet: Identifiable {
        case studio(AIStudio), all
        var id: String {
            switch self {
            case .studio(let s): return "studio-\(s.id)"
            case .all: return "all"
            }
        }
    }

    var body: some View {
        if !store.aiStudios.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "AI Spotlight", subtitle: "See what each model can do")
                    Spacer()
                    Button("See all") { activeSheet = .all }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                .screenPadding()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.aiStudios.prefix(8)) { studio in
                            StudioCard(studio: studio) { activeSheet = .studio(studio) }
                                .frame(width: 220)
                        }
                    }
                    .screenPadding()
                }
            }
            .sheet(item: $activeSheet) { which in
                switch which {
                case .studio(let s): AIStudioDetailView(studio: s)
                case .all: AISpotlightView()
                }
            }
        }
    }
}

/// Compact portfolio card: a mini poster stack, the model's pitch and reach.
struct StudioCard: View {
    let studio: AIStudio
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // GlassSurface so the card picks up the real iOS 26 glassEffect
            // (and depth) instead of re-implementing the material fallback.
            GlassSurface(tint: studio.accent) {
                VStack(alignment: .leading, spacing: 10) {
                    posterStack
                    Text(studio.name)
                        .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(studio.tagline)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        miniStat("\(studio.titleCount)", "titles")
                        miniStat("\(studio.totalSales)", "sold")
                        miniStat("\(studio.averageScore)", "avg")
                    }
                }
                .padding(12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerL, style: .continuous)
                    .strokeBorder(studio.accent.opacity(0.4), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(studio.name). \(studio.tagline) \(studio.titleCount) titles, \(studio.totalSales) sold.")
        .accessibilityAddTraits(.isButton)
    }

    private var posterStack: some View {
        ZStack {
            ForEach(Array(studio.showcase.prefix(3).enumerated()), id: \.element.id) { index, item in
                PosterArt(item: item, showsTitle: false)
                    .frame(width: 58, height: 86)
                    .rotationEffect(.degrees(Double(index - 1) * 8))
                    .offset(x: CGFloat(index - 1) * 30)
                    .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
                    .zIndex(index == 1 ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A single AI model's portfolio: its pitch, capabilities, reach, and a showreel
/// of its best titles.
struct AIStudioDetailView: View {
    let studio: AIStudio
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ledger: AICoinLedger
    @State private var selected: MediaItem?

    private var isOnChain: Bool { ledger.agents.contains { $0.name == studio.name } }

    var body: some View {
        ZStack {
            AppBackground(glow: studio.accent).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    statRow
                    if isOnChain { onChainCard }
                    capabilities
                    showreel
                }
                .padding(.bottom, 40)
            }
            HStack {
                CircleIconButton(icon: "chevron.down") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .sheet(item: $selected) { MediaDetailView(item: $0) }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [studio.accent.opacity(0.85), studio.accent.opacity(0.2), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 230)
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                Text(studio.name)
                    .font(.system(size: 32, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text(studio.tagline)
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 8) {
                    ForEach(studio.types) { type in
                        Chip(text: type.plural, systemImage: type.icon, color: .white)
                    }
                }
            }
            .padding(20)
        }
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            stat("\(studio.titleCount)", "Titles shipped", "square.stack.fill")
            stat("\(studio.totalSales)", "Copies sold", "cart.fill")
            stat("\(studio.averageScore)", "Avg AI score", "checkmark.seal.fill")
        }
        .screenPadding()
    }

    private func stat(_ value: String, _ label: String, _ icon: String) -> some View {
        GlassCard {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(studio.accent)
                Text(value).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var capabilities: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "What it can do").screenPadding()
            FlexibleHStack(spacing: 8, lineSpacing: 8) {
                ForEach(studio.capabilities, id: \.self) { capability in
                    Chip(text: capability, systemImage: "checkmark", color: studio.accent, filled: true)
                }
            }
            .screenPadding()
        }
    }

    private var showreel: some View {
        MediaRow(title: "Showreel", subtitle: "Its best work, vetted by the AI Editor",
                 items: studio.showcase) { selected = $0 }
    }

    private var onChainCard: some View {
        let txs = ledger.transactions(involving: studio.name, limit: 4)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Creation energy (NRN)", subtitle: "Energy it has cycled through the float").screenPadding()
            GlassCard(tint: Theme.gold) {
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(AICoin.format(ledger.cycled(of: studio.name)))")
                            .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        Text("NRN cycled").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Text("\(AICoin.format(ledger.inUse(of: studio.name))) in use")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                    ForEach(txs) { tx in
                        HStack(spacing: 8) {
                            Image(systemName: tx.from == studio.name ? "arrow.up.right" : "arrow.down.left")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(tx.from == studio.name ? Theme.inkSoft : Theme.success)
                            Text(tx.from == studio.name ? "returned to float" : "drew from float")
                                .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text("· \(tx.memo)").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                            Spacer()
                            Text("\(AICoin.format(tx.amount))").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                        }
                    }
                }
            }
            .screenPadding()
        }
    }
}
