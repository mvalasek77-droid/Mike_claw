import SwiftUI

/// Dedicated charts surface: a ranked Top 10 and a Trending leaderboard,
/// switchable by media type.
struct ChartsView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @State private var mode: Mode = .top10
    @State private var type: MediaType?
    @State private var selected: MediaItem?

    enum Mode: String, CaseIterable { case top10 = "Top 10", trending = "Trending" }

    private var items: [MediaItem] {
        let base = mode == .top10 ? store.topTen : store.trending
        let scoped = type.map { t in base.filter { $0.type == t } } ?? base
        return mode == .top10 ? Array(scoped.prefix(10)) : scoped
    }

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Charts")
                        .font(.displayL)
                        .foregroundStyle(Theme.ink)
                        .screenPadding()
                        .padding(.top, 8)

                    modeSwitch
                    typeFilter

                    if items.isEmpty {
                        EmptyStateView(icon: "chart.bar",
                                       title: "No \(type?.plural.lowercased() ?? "titles") \(mode == .top10 ? "charting" : "trending") yet",
                                       message: "Check back soon — the charts refresh as the marketplace moves.")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                ChartRow(rank: index + 1, item: item, metric: mode) { selected = item }
                            }
                        }
                        .screenPadding()
                    }
                }
                .padding(.bottom, 96)
            }
        }
        .sheet(item: $selected) { MediaDetailView(item: $0) }
    }

    private var modeSwitch: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button {
                    Motion.run(Motion.snap) { mode = m }
                    Haptics.selection()
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(mode == m ? .black : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(mode == m ? Color.white : Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
        }
        .screenPadding()
    }

    private var typeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, "All")
                ForEach(MediaType.allCases) { chip($0, $0.plural) }
            }
            .screenPadding()
        }
    }

    private func chip(_ t: MediaType?, _ label: String) -> some View {
        let active = type == t
        return Button {
            Motion.run(Motion.snap) { type = t }
            Haptics.selection()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? .black : Theme.inkSoft)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(active ? (t?.accent ?? .white) : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct ChartRow: View {
    let rank: Int
    let item: MediaItem
    let metric: ChartsView.Mode
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(rank <= 3 ? Theme.gold : Theme.inkFaint)
                    .frame(width: 36, alignment: .center)

                PosterArt(item: item, showsTitle: false)
                    .frame(width: 56, height: 80)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("\(item.categoryLabel) · \(item.genre)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 6) {
                        ScoreBadge(score: item.commercialScore, compact: true)
                        if metric == .top10 {
                            Label("\(item.purchases.formatted())", systemImage: "cart.fill")
                        } else {
                            Label("\(item.trending)", systemImage: "flame.fill")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Text(item.priceLabel)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }
}
