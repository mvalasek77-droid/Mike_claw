import SwiftUI

/// Attribution + technical explanation of where BoxCall's data comes from.
/// Reachable from Profile → "Data sources".
struct DataSourcesView: View {
    @EnvironmentObject var market: MarketService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusCard
                sources
                howItStaysFresh
                disclaimer
            }
            .padding()
        }
        .navigationTitle("Data Sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Where the catalog comes from")
                .font(.title3.bold())
            Text("BoxCall's upcoming-releases feed and real posters are pulled from public movie databases. Historical box-office grosses and pre-release tracking numbers, when available, are aggregated server-side.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live status").font(.headline)
                Spacer()
                if market.refreshInFlight {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            statRow("Provider",
                    Config.tmdbAPIKey.isEmpty ? "Mock (built-in slate)" : "TMDB /movie/upcoming")
            statRow("Catalog size", "\(market.movies.count) movies")
            if let last = market.lastRefreshAt {
                statRow("Last refresh", format(last))
            }
            if let err = market.lastRefreshError {
                statRow("Last error", err, color: .red)
            }
            statRow("Auto-refresh", "Every 6 hours + pull-to-refresh")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                Text("Upcoming releases").font(.headline)
                SourceRow(name: "TMDB — The Movie Database",
                          role: "Titles, posters, release dates, genres, studios, taglines.",
                          status: Config.tmdbAPIKey.isEmpty
                            ? "Not configured (add TMDB_API_KEY in Info.plist)"
                            : "Connected — fetched client-side, no proxy.",
                          wired: !Config.tmdbAPIKey.isEmpty)
                SourceRow(name: "IMDb Coming Soon",
                          role: "Broader upcoming calendar, especially indies TMDB is late on.",
                          status: "Aggregated by the backend at api.boxcall.com/upcoming (server-side scraper). Backend endpoint stubbed; degrades gracefully to TMDB.",
                          wired: false)
                SourceRow(name: "The Numbers — release schedule",
                          role: "Weekend-by-weekend slate + wide vs limited flags.",
                          status: "Same backend aggregator. Server-side scraper.",
                          wired: false)
            }
            Group {
                Text("Pre-release tracking (feeds the price setter)")
                    .font(.headline).padding(.top, 4)
                SourceRow(name: "Algorithmic estimate",
                          role: "Consensus opening + IV derived from TMDB popularity when nothing better is available. Always on as a fallback.",
                          status: "Live — powers the initial chain when the backend tracking endpoint has no data.",
                          wired: true)
                SourceRow(name: "Deadline Hollywood + NRG",
                          role: "Real pre-release tracking numbers.",
                          status: "Backend-only. Server pulls headline tracking each morning and serves it to the app via /tracking. Endpoint stubbed.",
                          wired: false)
                SourceRow(name: "The Numbers — historical grosses",
                          role: "Genre / budget cohorts for IV calibration.",
                          status: "Backend-only. Scraper feeds a per-genre volatility model.",
                          wired: false)
            }
            Group {
                Text("Social signals (adjusts consensus ±30%)")
                    .font(.headline).padding(.top, 4)
                SourceRow(name: "YouTube trailer engagement",
                          role: "Trailer views (7-day) and like ratio via YouTube Data API v3. Bullish trailer stats shift consensus up and tighten IV.",
                          status: Config.youtubeAPIKey.isEmpty
                            ? "Not configured (add YOUTUBE_API_KEY in Info.plist)"
                            : "Connected — fetched client-side.",
                          wired: !Config.youtubeAPIKey.isEmpty)
                SourceRow(name: "X (Twitter) mention velocity + sentiment",
                          role: "24h mention volume + sentiment score. High velocity + positive sentiment lifts the crowd forecast.",
                          status: "Backend-only. Paid X API tier proxied through api.boxcall.com/x-signal. Endpoint stubbed.",
                          wired: false)
            }
            Group {
                Text("Settlement").font(.headline).padding(.top, 4)
                SourceRow(name: "Box Office Mojo (IMDb)",
                          role: "Actual reported Fri–Sun domestic gross. Drives Monday settlement of every open position.",
                          status: "Backend-only in production. No public API — scraped by the server, then applied via settle() on Monday morning.",
                          wired: false)
                SourceRow(name: "IMDb",
                          role: "Cast / crew metadata for review context.",
                          status: "Paid data licensing — reserved for a later phase.",
                          wired: false)
            }
            Group {
                Text("Pricing").font(.headline).padding(.top, 4)
                SourceRow(name: "PriceSetter",
                          role: "Sets the theoretical premium for each strike from consensus + IV + days-to-expiry. Emits a 5-strike-per-side chain when a new movie is added, or re-anchors an existing chain when real tracking arrives.",
                          status: "Live. Formula: intrinsic + consensus × IV × √(DTE/30) × exp(-|moneyness| × 1.8) × 0.5.",
                          wired: true)
                SourceRow(name: "MarketMaker",
                          role: "Once the chain is live, market makers step in at rolling support/resistance so premiums mean-revert inside a band. Real user flow overrides.",
                          status: "Live. See the Learn section on the live market.",
                          wired: true)
            }
        }
    }

    private var howItStaysFresh: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How the app stays fresh").font(.headline)
            bullet("On launch", "Kicks off a refresh from the current provider. Falls back to the last cached catalog if the network fails.")
            bullet("Every 6 hours", "A background timer re-fetches while the app is open. New releases stream in and get a NEW badge on the Slate.")
            bullet("Pull to refresh", "Manual override — swipe down on the Slate any time.")
            bullet("Positions survive", "Refresh merges data. A movie you're already holding never disappears mid-cycle, even if the provider stops listing it before opening.")
            bullet("Auto-prune", "Once a movie has opened AND you have no open positions on it, it drops off the Slate on the next refresh.")
        }
    }

    private var disclaimer: some View {
        Text("BoxCall is not affiliated with TMDB, IMDb, Amazon, Box Office Mojo, The Numbers, or Deadline. All trademarks belong to their respective owners. Data used under each provider's public terms.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private func statRow(_ k: String, _ v: String, color: Color = .primary) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption.monospacedDigit()).foregroundStyle(color)
        }
    }

    private func bullet(_ head: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.forward.circle").foregroundStyle(.orange).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(head).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func format(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d 'at' h:mm a"
        return f.string(from: d)
    }
}

private struct SourceRow: View {
    let name: String
    let role: String
    let status: String
    let wired: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline.weight(.bold))
                Spacer()
                Text(wired ? "LIVE" : "PLANNED")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill((wired ? Color.green : .gray).opacity(0.25)))
                    .foregroundStyle(wired ? .green : .secondary)
            }
            Text(role).font(.caption).foregroundStyle(.secondary)
            Text(status).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}
