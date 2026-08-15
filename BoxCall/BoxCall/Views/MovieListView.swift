import SwiftUI

struct MovieListView: View {
    @EnvironmentObject var market: MarketService
    @EnvironmentObject var portfolio: PortfolioService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CoinBalanceRow(coins: portfolio.user.reelCoins)
                }
                Section("Opening soon") {
                    ForEach(market.movies) { movie in
                        NavigationLink(value: movie) {
                            MovieRow(movie: movie)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("BoxCall")
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie)
            }
        }
    }
}

struct CoinBalanceRow: View {
    let coins: Double
    var body: some View {
        HStack {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Reel Coins")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(coins, format: .number.precision(.fractionLength(0)))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer()
            Text("+500 / week")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct MovieRow: View {
    let movie: Movie
    @EnvironmentObject var market: MarketService

    var body: some View {
        let implied = market.impliedConsensus(for: movie.id)
        let delta = market.consensusDeltaPct(for: movie.id)
        HStack(spacing: 14) {
            Text(movie.posterEmoji)
                .font(.system(size: 40))
                .frame(width: 56, height: 72)
                .background(RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title).font(.headline)
                Text(movie.studio).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Label("\(movie.daysToRelease)d", systemImage: "clock")
                    HStack(spacing: 3) {
                        Image(systemName: "chart.bar")
                        Text("$\(implied, specifier: "%.1f")M")
                        Text(delta * 100, format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                            .foregroundStyle(delta >= 0 ? .green : .red)
                        Text("%").foregroundStyle(delta >= 0 ? .green : .red)
                    }
                    Label("\(Int(movie.impliedVolPct))% IV", systemImage: "waveform.path")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Sparkline(points: market.consensusHistoryFor(movieId: movie.id),
                          color: delta >= 0 ? .green : .red,
                          height: 14)
            }
        }
        .padding(.vertical, 4)
    }
}
