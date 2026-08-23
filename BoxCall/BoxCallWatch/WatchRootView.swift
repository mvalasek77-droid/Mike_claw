import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject var bridge: WatchBridge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let s = bridge.snapshot {
                    nextOpening(s)
                    Divider()
                    topPosition(s)
                    Divider()
                    Text("Updated \(s.updatedAt, style: .relative) ago")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Waiting for iPhone…")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("BoxCall")
    }

    private func nextOpening(_ s: WatchBridge.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next opening").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(s.nextMoviePoster).font(.title3)
                Text(s.nextMovieTitle).font(.headline).lineLimit(1)
            }
            Text("Opens in \(s.nextMovieOpensIn)d")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func topPosition(_ s: WatchBridge.Snapshot) -> some View {
        if let movie = s.topPositionMovie {
            VStack(alignment: .leading, spacing: 4) {
                Text("Top position").font(.caption2).foregroundStyle(.secondary)
                Text(movie).font(.subheadline).lineLimit(1)
                Text(s.topPositionSideLabel ?? "—")
                    .font(.caption.weight(.bold))
                    .foregroundStyle((s.topPositionSideLabel ?? "").hasPrefix("CALL") ? .green : .red)
                HStack {
                    if let mark = s.topPositionMark {
                        Text("Mark \(mark, specifier: "%.2f")").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let pnl = s.topPositionPnL {
                        Text(pnl, format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(pnl >= 0 ? .green : .red)
                    }
                }
            }
        } else {
            Text("No open positions").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
