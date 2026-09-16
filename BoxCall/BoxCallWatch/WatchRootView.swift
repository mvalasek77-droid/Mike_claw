import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject var bridge: WatchBridge

    var body: some View {
        if let s = bridge.snapshot {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        balanceHeader(s)
                        Divider()
                        nextOpening(s)
                        Divider()
                        positionsSection(s)
                        updatedFooter(s)
                    }
                    .padding(.horizontal, 4)
                }
                .navigationTitle("BoxCall")
            }
        } else {
            VStack(spacing: 8) {
                Text("🎬").font(.largeTitle)
                Text("Open BoxCall on iPhone to sync your portfolio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .onAppear { bridge.refresh() }
        }
    }

    // MARK: - Balance header

    private func balanceHeader(_ s: WatchBridge.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Balance").font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(s.balance)) RC")
                .font(.title3.bold().monospacedDigit())
            HStack(spacing: 4) {
                Image(systemName: s.totalPnL >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2.bold())
                Text(s.totalPnL, format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                    .font(.caption.bold().monospacedDigit())
            }
            .foregroundStyle(s.totalPnL >= 0 ? .green : .red)
        }
    }

    // MARK: - Next opening

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

    // MARK: - Positions list

    @ViewBuilder
    private func positionsSection(_ s: WatchBridge.Snapshot) -> some View {
        let open = s.positions.filter { !$0.isSettled }
        let settled = s.positions.filter { $0.isSettled }

        if open.isEmpty && settled.isEmpty {
            Text("No trades yet")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            if !open.isEmpty {
                Text("Open trades").font(.caption2).foregroundStyle(.secondary)
                ForEach(open) { p in positionRow(p) }
            }
            if !settled.isEmpty {
                Text("Settled").font(.caption2).foregroundStyle(.secondary)
                    .padding(.top, open.isEmpty ? 0 : 4)
                ForEach(settled) { p in positionRow(p) }
            }
        }
    }

    private func positionRow(_ p: WatchBridge.PositionSnap) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(p.movieEmoji)
                Text(p.movieTitle).font(.caption.weight(.semibold)).lineLimit(1)
            }
            HStack {
                Text(p.sideLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(p.sideLabel.hasPrefix("CALL") ? .green : .red)
                Text("$\(Int(p.strikeMillions))M")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Spacer()
                Text(p.pnl, format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(p.pnl >= 0 ? .green : .red)
            }
            if p.isSettled, let payout = p.settledPayout {
                Text("Payout: \(payout, specifier: "%.1f") RC")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 0) {
                    Text("qty \(p.quantity) · mark ")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(p.mark, format: .number.precision(.fractionLength(2)))
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.15)))
    }

    // MARK: - Footer

    private func updatedFooter(_ s: WatchBridge.Snapshot) -> some View {
        Text("Updated \(s.updatedAt, style: .relative) ago")
            .font(.system(size: 9)).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }
}
