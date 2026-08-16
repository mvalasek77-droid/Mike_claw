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
        VStack(alignment: .leading, spacing: 10) {
            Text("Aggregated sources").font(.headline)
            SourceRow(name: "TMDB — The Movie Database",
                      role: "Upcoming releases, posters, studios, release dates, genres, taglines.",
                      status: Config.tmdbAPIKey.isEmpty
                        ? "Not configured (add TMDB_API_KEY in Info.plist)"
                        : "Connected — fetched client-side.",
                      wired: !Config.tmdbAPIKey.isEmpty)
            SourceRow(name: "Box Office Mojo (IMDb)",
                      role: "Actual opening-weekend grosses. Drives Monday settlement.",
                      status: "Backend-only in production. No public API — pulled via server-side scraper on the boxcall.com API.",
                      wired: false)
            SourceRow(name: "The Numbers",
                      role: "Historical opening-weekend history for IV calibration.",
                      status: "Backend-only. Same scraping strategy.",
                      wired: false)
            SourceRow(name: "Deadline Hollywood",
                      role: "Pre-release tracking (consensus estimates from NRG-style reports).",
                      status: "Backend-only. Server pulls headline tracking numbers each morning.",
                      wired: false)
            SourceRow(name: "IMDb",
                      role: "Cast / crew metadata for review context.",
                      status: "Paid data licensing — reserved for a later phase.",
                      wired: false)
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
