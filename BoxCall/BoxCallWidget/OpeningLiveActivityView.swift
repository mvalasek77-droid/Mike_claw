import ActivityKit
import WidgetKit
import SwiftUI

/// The widget-target rendering of the opening-day Live Activity.
/// Same ContentState shape as the app side (mirrored here so the
/// extension can decode without depending on the app target).
struct OpeningLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var impliedConsensusM: Double
        var yourPositionSide: String
        var yourPositionMark: Double
        var yourPositionEntry: Double
        var yourPositionPnL: Double
        var actualOpeningM: Double?
    }
    let movieId: String
    let movieTitle: String
    let moviePoster: String
    let opensAt: Date
}

struct OpeningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OpeningLiveActivityAttributes.self) { context in
            lockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.moviePoster).font(.system(size: 28))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.yourPositionPnL,
                         format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(context.state.yourPositionPnL >= 0 ? .green : .red)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.movieTitle).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.yourPositionSide).font(.caption)
                        Spacer()
                        if let a = context.state.actualOpeningM {
                            Text("Opened $\(a, specifier: "%.1f")M").font(.caption)
                        } else {
                            Text("Opens \(context.attributes.opensAt, style: .relative)").font(.caption)
                        }
                    }
                }
            } compactLeading: {
                Text(context.attributes.moviePoster)
            } compactTrailing: {
                Text(context.state.yourPositionPnL,
                     format: .number.precision(.fractionLength(0)).sign(strategy: .always()))
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(context.state.yourPositionPnL >= 0 ? .green : .red)
            } minimal: {
                Text(context.attributes.moviePoster)
            }
        }
    }

    @ViewBuilder
    private func lockScreen(context: ActivityViewContext<OpeningLiveActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Text(context.attributes.moviePoster).font(.system(size: 40))
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.movieTitle).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(context.state.yourPositionSide).font(.caption.weight(.bold))
                    Text("· mark \(context.state.yourPositionMark, specifier: "%.2f")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let actual = context.state.actualOpeningM {
                    Text("Opened at $\(actual, specifier: "%.1f")M")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Implied $\(context.state.impliedConsensusM, specifier: "%.1f")M · opens \(context.attributes.opensAt, style: .relative)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("P&L").font(.caption2).foregroundStyle(.secondary)
                Text(context.state.yourPositionPnL,
                     format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(context.state.yourPositionPnL >= 0 ? .green : .red)
            }
        }
        .padding()
    }
}
