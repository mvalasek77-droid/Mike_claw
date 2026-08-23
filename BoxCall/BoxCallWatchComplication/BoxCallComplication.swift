import WidgetKit
import SwiftUI

/// Watch complication — appears on the watch face. Shows the current
/// top-position P&L or, if no positions, the next opening.
struct BoxCallComplication: Widget {
    let kind = "BoxCallComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.orange.gradient, for: .widget)
        }
        .configurationDisplayName("BoxCall")
        .description("Top position P&L or next opening.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchBridge.Snapshot?
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in ctx: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), snapshot: nil)
    }
    func getSnapshot(in ctx: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: Date(), snapshot: WatchBridge.shared.snapshot))
    }
    func getTimeline(in ctx: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = ComplicationEntry(date: Date(), snapshot: WatchBridge.shared.snapshot)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct ComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(s?.nextMoviePoster ?? "🎬").font(.title3)
                if let pnl = s?.topPositionPnL {
                    Text(pnl, format: .number.precision(.fractionLength(0)).sign(strategy: .always()))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(pnl >= 0 ? .green : .red)
                } else if let d = s?.nextMovieOpensIn {
                    Text("\(d)d").font(.caption2)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(s?.nextMoviePoster ?? "🎬")
                    Text(s?.topPositionMovie ?? s?.nextMovieTitle ?? "BoxCall").font(.caption).lineLimit(1)
                }
                if let pnl = s?.topPositionPnL, let side = s?.topPositionSideLabel {
                    HStack {
                        Text(side).font(.caption2.weight(.bold))
                            .foregroundStyle(side.hasPrefix("CALL") ? .green : .red)
                        Spacer()
                        Text(pnl, format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundStyle(pnl >= 0 ? .green : .red)
                    }
                } else if let d = s?.nextMovieOpensIn {
                    Text("Opens in \(d)d").font(.caption2)
                }
            }
        default:
            if let pnl = s?.topPositionPnL {
                Text("BoxCall  \(pnl, specifier: "%+.2f") RC")
            } else if let d = s?.nextMovieOpensIn {
                Text("BoxCall  opens in \(d)d")
            } else {
                Text("BoxCall")
            }
        }
    }
}
