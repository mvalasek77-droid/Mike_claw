import WidgetKit
import SwiftUI

struct NextOpeningWidget: Widget {
    let kind = "BoxCallNextOpening"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            NextOpeningEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next opening")
        .description("The movie opening soonest, with the current implied consensus.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextOpeningEntryView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let s = entry.snapshot
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 6) {
                Text(s.nextMoviePoster).font(.system(size: 32))
                Text(s.nextMovieTitle).font(.headline).lineLimit(2)
                Spacer()
                Text("Opens in \(s.nextMovieOpensIn)d").font(.caption).foregroundStyle(.secondary)
                Text("$\(s.nextMovieImpliedConsensus, specifier: "%.1f")M implied")
                    .font(.caption.monospacedDigit()).foregroundStyle(.orange)
            }
        } else {
            HStack(spacing: 12) {
                Text(s.nextMoviePoster).font(.system(size: 48))
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.nextMovieTitle).font(.title3.bold()).lineLimit(2)
                    HStack {
                        Label("\(s.nextMovieOpensIn)d", systemImage: "clock")
                        Label("$\(s.nextMovieImpliedConsensus, specifier: "%.1f")M",
                              systemImage: "chart.bar")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Text("BoxCall").font(.caption2.weight(.heavy)).foregroundStyle(.orange)
                }
                Spacer()
            }
        }
    }
}
