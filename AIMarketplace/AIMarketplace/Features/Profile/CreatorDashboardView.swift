import SwiftUI

/// App Store Connect-style analytics for content makers: units, proceeds, your
/// 85% share, a sales trend, and per-title performance. Available to anyone who
/// has published a title.
struct CreatorDashboardView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss

    private var titles: [MediaItem] { store.liveTitles }
    private var totalUnits: Int { titles.reduce(0) { $0 + $1.purchases } }
    private var grossRevenue: Double { titles.reduce(0) { $0 + Double($1.purchases) * $1.price } }
    private var proceeds: Double { grossRevenue * Commerce.creatorShareRate }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if titles.isEmpty {
                        emptyState
                    } else {
                        kpiRow
                        trendCard
                        titlesCard
                        payoutCard
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.kdp).ignoresSafeArea())
            .navigationTitle("Creator Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var kpiRow: some View {
        HStack(spacing: 10) {
            kpi("Units", "\(totalUnits)", "cart.fill", Theme.accent)
            kpi("Proceeds", String(format: "$%.0f", proceeds), "dollarsign.circle.fill", Theme.success)
            kpi("Titles", "\(titles.count)", "square.stack.fill", Theme.kdp)
        }
    }

    private func kpi(_ label: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                Text(value).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trendCard: some View {
        GlassCard(title: "Sales · last 7 days", icon: "chart.bar.fill", tint: Theme.accent) {
            BarChart(values: syntheticWeek(total: totalUnits))
                .frame(height: 130)
        }
    }

    private var titlesCard: some View {
        GlassCard(title: "By title", icon: "list.bullet.rectangle.portrait", tint: Theme.kdp) {
            VStack(spacing: 12) {
                ForEach(titles) { item in
                    HStack(spacing: 12) {
                        PosterArt(item: item, showsTitle: false).frame(width: 40, height: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text("\(item.purchases) units · \(item.scoreLabel) score").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        Text(String(format: "$%.0f", Double(item.purchases) * item.price * Commerce.creatorShareRate))
                            .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Theme.success)
                    }
                }
            }
        }
    }

    private var payoutCard: some View {
        GlassCard(title: "Estimated payout", icon: "banknote.fill", tint: Theme.success) {
            VStack(alignment: .leading, spacing: 8) {
                payRow("Gross sales", grossRevenue, Theme.ink)
                payRow("Service fee (15%)", -grossRevenue * Commerce.platformFeeRate, Theme.warning)
                Divider().overlay(Theme.hairline)
                payRow("Your proceeds (85%)", proceeds, Theme.success, bold: true)
                Text(Commerce.appleFeeNote)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private func payRow(_ label: String, _ amount: Double, _ color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 13, weight: bold ? .bold : .medium, design: .rounded)).foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(String(format: "%@$%.2f", amount < 0 ? "−" : "", abs(amount)))
                .font(.system(size: bold ? 17 : 14, weight: .heavy, design: .rounded)).foregroundStyle(color)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 46)).foregroundStyle(Theme.inkFaint)
            Text("No sales data yet").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text("Publish a title and its performance — units, proceeds and trends — will appear here.")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 30)
    }

    /// Deterministic 7-point distribution of the unit total for the trend bars.
    private func syntheticWeek(total: Int) -> [Double] {
        guard total > 0 else { return Array(repeating: 0, count: 7) }
        let weights = [0.10, 0.12, 0.14, 0.13, 0.16, 0.18, 0.17]
        return weights.map { Double(total) * $0 }
    }
}

/// Lightweight bar chart — no external framework dependency.
struct BarChart: View {
    let values: [Double]
    private var maxValue: Double { max(values.max() ?? 1, 1) }
    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        GeometryReader { geo in
            let barWidth = (geo.size.width - CGFloat(values.count - 1) * 8) / CGFloat(values.count)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.brandGradient)
                            .frame(width: barWidth,
                                   height: max(4, (geo.size.height - 22) * CGFloat(value / maxValue)))
                        Text(labels[index % labels.count])
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }
}
