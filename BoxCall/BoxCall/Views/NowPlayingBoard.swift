import SwiftUI

/// The board above the Marquee feed: what is opening next, what the
/// trades project it will do, and where the crowd has moved that number
/// since.
///
/// Every tile is a way into the film's page. The feed underneath is
/// opinion; this is the schedule the opinions are about.
struct NowPlayingBoard: View {
    @EnvironmentObject var market: MarketService

    /// Next few openings, soonest first. Films that already opened are
    /// filtered out upstream by the catalog.
    private var upcoming: [Movie] {
        market.movies
            .filter { $0.daysToRelease >= 0 }
            .sorted { $0.releaseDate < $1.releaseDate }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            header
            if upcoming.isEmpty {
                Text("No films on the board. Pull to refresh the slate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Space.md)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.md) {
                        ForEach(upcoming) { movie in
                            NavigationLink(value: movie) {
                                BoardTile(movie: movie,
                                          implied: market.impliedConsensus(for: movie.id),
                                          deltaPct: market.consensusDeltaPct(for: movie.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.sm) {
            Text("ON THE BOARD")
                .font(.system(size: 11, weight: .heavy))
                .tracking(2)
                .foregroundStyle(Theme.marqueeGold)
            Rectangle()
                .fill(Theme.marqueeGold.opacity(0.30))
                .frame(height: 1)
            Text("\(upcoming.count)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
}

/// One film on the board, styled as a marquee card.
struct BoardTile: View {
    let movie: Movie
    /// The live crowd-adjusted opening number, in $M.
    let implied: Double
    /// How far that has moved from the film's standing estimate.
    let deltaPct: Double

    private var days: Int { movie.daysToRelease }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .top) {
                Text(movie.posterEmoji).font(.title2)
                Spacer(minLength: 4)
                countdownPill
            }

            Text(movie.title)
                .font(.system(.subheadline, design: .serif).weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(movie.studio)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            projectionBlock
        }
        .padding(Theme.Space.md)
        .frame(width: 168, height: 190, alignment: .topLeading)
        .glassSurface(radius: Theme.Radius.md,
                      tint: Theme.marqueeGold.opacity(0.05),
                      stroke: Theme.marqueeGold.opacity(0.22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y)
        .accessibilityHint("Opens \(movie.title)")
    }

    private var countdownPill: some View {
        Text(days == 0 ? "TONIGHT" : "\(days)d")
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.5)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(days <= 7
                    ? Theme.marqueeGold.opacity(0.22)
                    : Color.primary.opacity(0.08))
            )
            .foregroundStyle(days <= 7 ? Theme.marqueeGold : .secondary)
    }

    /// The number, and where it came from.
    ///
    /// When a trade has published a range, the tile shows that range and
    /// the live crowd-adjusted figure beside it, so the two are never
    /// confused for one another.
    @ViewBuilder
    private var projectionBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$\(implied, specifier: "%.0f")M")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if abs(deltaPct) >= 0.005 {
                    Text("\(deltaPct >= 0 ? "▲" : "▼")\(abs(deltaPct) * 100, specifier: "%.0f")%")
                        .font(.system(size: 9, weight: .heavy).monospacedDigit())
                        .foregroundStyle(deltaPct >= 0 ? Theme.bull : Theme.bear)
                }
            }
            if let projection = movie.tradeProjection, projection.isPublished {
                Text("Trades: $\(Int(projection.lowMillions))–\(Int(projection.highMillions))M")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Opening weekend est.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .animation(Theme.Motion.smooth, value: implied)
    }

    private var a11y: String {
        var parts = [movie.title, movie.studio]
        parts.append(days == 0 ? "opens tonight" : "opens in \(days) days")
        if let p = movie.tradeProjection, p.isPublished {
            parts.append("trades project \(Int(p.lowMillions)) to \(Int(p.highMillions)) million")
        }
        parts.append("crowd-adjusted \(Int(implied)) million")
        return parts.joined(separator: ", ")
    }
}
