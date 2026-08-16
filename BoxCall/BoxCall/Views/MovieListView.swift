import SwiftUI

struct MovieListView: View {
    @EnvironmentObject var market: MarketService
    @EnvironmentObject var portfolio: PortfolioService

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CoinBalanceRow(coins: portfolio.user.reelCoins)
                    LowBalanceBanner()
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(market.movies) { movie in
                        NavigationLink(value: movie) {
                            MovieRow(movie: movie)
                        }
                    }
                } header: {
                    catalogHeader
                } footer: {
                    catalogFooter
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await market.refreshCatalog() }
            .navigationTitle("BoxCall")
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await market.refreshCatalog() }
                    } label: {
                        if market.refreshInFlight {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(market.refreshInFlight)
                }
            }
        }
    }

    private var catalogHeader: some View {
        HStack {
            Text("Opening soon")
            Spacer()
            if let last = market.lastRefreshAt {
                Text("Updated \(short(last))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var catalogFooter: some View {
        if let err = market.lastRefreshError {
            Text("Refresh failed: \(err). Showing cached slate.")
                .font(.caption2)
                .foregroundStyle(.red)
        } else if Config.tmdbAPIKey.isEmpty {
            Text("Showing built-in demo slate. Add a TMDB_API_KEY in Info.plist to pull live upcoming releases. Pull down to refresh.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("Pull down to refresh. Auto-refreshes every 6 hours.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func short(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

struct CoinBalanceRow: View {
    let coins: Double
    @EnvironmentObject var portfolio: PortfolioService
    var body: some View {
        let m = portfolio.user.membership
        HStack {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Reel Coins")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if m.isPaid {
                        Text(m.displayName)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(m.accentColor.opacity(0.25)))
                            .foregroundStyle(m.accentColor)
                    }
                }
                Text(coins, format: .number.precision(.fractionLength(0)))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer()
            Text("+\(Int(m.weeklyAllowance)) / week")
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
            PosterThumb(url: movie.posterURL, emoji: movie.posterEmoji)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(movie.title).font(.headline)
                    if movie.isNewlyAdded {
                        Text("NEW")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.orange))
                    }
                }
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

/// Poster thumbnail with graceful fallback: try the URL, drop back
/// to the emoji stamp if it fails or is missing.
struct PosterThumb: View {
    let url: String?
    let emoji: String
    var width: CGFloat = 56
    var height: CGFloat = 72

    var body: some View {
        Group {
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        emojiFallback
                    }
                }
            } else {
                emojiFallback
            }
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.2)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emojiFallback: some View {
        Text(emoji).font(.system(size: min(width, height) * 0.55))
    }
}
