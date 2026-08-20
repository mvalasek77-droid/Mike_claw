import WidgetKit
import SwiftUI

struct TopPositionWidget: Widget {
    let kind = "BoxCallTopPosition"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            TopPositionEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Top position")
        .description("Your biggest open position with live P&L.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TopPositionEntryView: View {
    let entry: SnapshotEntry

    var body: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top position").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("BoxCall").font(.caption2.weight(.heavy)).foregroundStyle(.orange)
            }
            if let movie = s.topPositionMovie {
                Text(movie).font(.headline).lineLimit(1)
                Text(s.topPositionSideLabel ?? "—")
                    .font(.caption.weight(.bold))
                    .foregroundStyle((s.topPositionSideLabel ?? "").hasPrefix("CALL") ? .green : .red)
                Spacer(minLength: 2)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mark").font(.caption2).foregroundStyle(.secondary)
                        Text(s.topPositionMark ?? 0, format: .number.precision(.fractionLength(2)))
                            .font(.caption.monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("P&L").font(.caption2).foregroundStyle(.secondary)
                        Text(s.topPositionPnL ?? 0,
                             format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle((s.topPositionPnL ?? 0) >= 0 ? .green : .red)
                    }
                }
            } else {
                Text("No open positions").font(.subheadline).foregroundStyle(.secondary)
                Text("Head to Slate to place a trade.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
