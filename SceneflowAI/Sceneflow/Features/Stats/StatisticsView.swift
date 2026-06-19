import SwiftUI
import Charts

/// Live analytics for the script: page count, runtime, scene mix, and which
/// characters carry the dialogue. Helpful both for craft (is my lead actually
/// the lead?) and for production planning.
struct StatisticsView: View {
    let screenplay: Screenplay

    private var analytics: ScriptAnalytics { ScriptAnalytics(screenplay) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                metricGrid

                if analytics.interiorScenes + analytics.exteriorScenes > 0 {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Scene setting")
                            HStack(spacing: 16) {
                                settingBar(label: "INT", value: analytics.interiorScenes,
                                           total: analytics.interiorScenes + analytics.exteriorScenes,
                                           color: Palette.ink)
                                settingBar(label: "EXT", value: analytics.exteriorScenes,
                                           total: analytics.interiorScenes + analytics.exteriorScenes,
                                           color: Palette.accent)
                            }
                        }
                    }
                }

                if !analytics.dialogueByCharacter.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Dialogue distribution")
                            Chart(Array(analytics.dialogueByCharacter.prefix(8))) { item in
                                BarMark(
                                    x: .value("Words", item.words),
                                    y: .value("Character", item.name)
                                )
                                .foregroundStyle(Palette.marqueeGradient)
                                .cornerRadius(4)
                            }
                            .chartXAxis { AxisMarks() }
                            .frame(height: CGFloat(min(8, analytics.dialogueByCharacter.count)) * 34 + 20)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Word counts")
                        statRow("Total words", "\(analytics.wordCount)")
                        statRow("Dialogue", "\(analytics.dialogueWordCount)")
                        statRow("Action", "\(analytics.actionWordCount)")
                        if analytics.wordCount > 0 {
                            let pct = Int(Double(analytics.dialogueWordCount) / Double(analytics.wordCount) * 100)
                            statRow("Dialogue ratio", "\(pct)%")
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(value: String(format: "%.0f", analytics.pageCount), label: "Pages", symbol: "doc.fill")
            MetricTile(value: analytics.runtime, label: "Runtime", symbol: "clock.fill")
            MetricTile(value: "\(analytics.sceneCount)", label: "Scenes", symbol: "film.fill")
            MetricTile(value: "\(screenplay.characterNames.count)", label: "Characters", symbol: "person.2.fill")
        }
    }

    private func settingBar(label: String, value: Int, total: Int, color: Color) -> some View {
        let fraction = total > 0 ? Double(value) / Double(total) : 0
        return VStack(spacing: 6) {
            Text("\(value)").font(.title2.bold()).foregroundStyle(Palette.primaryText)
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color).frame(height: max(4, geo.size.height * fraction))
                }
            }
            .frame(height: 60)
            Text(label).font(.caption.weight(.bold)).foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.secondaryText)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(Palette.primaryText)
        }
        .font(.subheadline)
    }
}

struct MetricTile: View {
    var value: String
    var label: String
    var symbol: String

    var body: some View {
        GlassCard(tier: .raised) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Palette.accent)
                Text(value)
                    .font(.title.bold())
                    .foregroundStyle(Palette.primaryText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
