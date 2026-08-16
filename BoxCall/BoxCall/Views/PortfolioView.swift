import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject var portfolio: PortfolioService
    @EnvironmentObject var market: MarketService

    var openPositions: [Position] { portfolio.positions.filter { $0.isOpen } }
    var settledPositions: [Position] { portfolio.positions.filter { !$0.isOpen } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    balanceCard
                    LowBalanceBanner()
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                Section("Open positions") {
                    if openPositions.isEmpty {
                        Text("No open trades. Head to Slate to place your first one.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(openPositions) { p in
                            PositionRow(position: p)
                        }
                    }
                }
                if !settledPositions.isEmpty {
                    Section("Settled") {
                        ForEach(settledPositions) { p in
                            PositionRow(position: p)
                        }
                    }
                }
                Section {
                    Button {
                        simulateAllSettlements()
                    } label: {
                        Label("Simulate opening weekends (demo)", systemImage: "sparkles")
                    }
                }
            }
            .navigationTitle("Portfolio")
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reel Coins").font(.caption).foregroundStyle(.secondary)
            Text(portfolio.user.reelCoins, format: .number.precision(.fractionLength(0)))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            HStack {
                Label("Lifetime", systemImage: "chart.line.uptrend.xyaxis")
                Spacer()
                Text(portfolio.user.lifetimePnL, format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
                    .foregroundStyle(portfolio.user.lifetimePnL >= 0 ? .green : .red)
                    .monospacedDigit()
            }
            .font(.caption)
            HStack(spacing: 4) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(.orange)
                Text("Next Monday reset · +\(Int(portfolio.user.membership.weeklyAllowance)) RC in \(RefillClock.countdownString())")
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
        .padding(.vertical, 6)
    }

    private func simulateAllSettlements() {
        for movie in market.movies where movie.daysToRelease <= 14 {
            let actual = market.simulatedActualOW(for: movie)
            portfolio.settle(movieId: movie.id, actualMillions: actual)
        }
        portfolio.refreshLeaderboard()
    }
}

struct PositionRow: View {
    let position: Position
    @EnvironmentObject var market: MarketService
    @EnvironmentObject var portfolio: PortfolioService

    var movie: Movie? { market.movie(id: position.movieId) }
    var currentMark: Double {
        market.chain(for: position.movieId).first { $0.id == position.contractId }?.premium ?? position.entryPremium
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(movie?.posterEmoji ?? "🎬").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(movie?.title ?? "—").fontWeight(.semibold)
                    Text("\(position.side.display) $\(Int(position.strikeMillions))M · qty \(position.quantity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                pnlBadge
            }
            if position.isOpen {
                HStack(spacing: 16) {
                    infoPair("Entry", position.entryPremium)
                    infoPair("Mark", currentMark)
                    Spacer()
                    Button("Close") {
                        portfolio.closeAtMark(position: position)
                        portfolio.refreshLeaderboard()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .font(.caption)
            } else if let actual = position.actualOWMillions {
                Text("Settled at $\(actual, specifier: "%.1f")M opening")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var pnlBadge: some View {
        let pnl = position.pnl(mark: currentMark)
        return Text(pnl, format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
            .font(.callout.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(pnl >= 0 ? .green : .red)
    }

    private func infoPair(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).foregroundStyle(.secondary)
            Text(value, format: .number.precision(.fractionLength(2)))
                .monospacedDigit()
        }
    }
}
