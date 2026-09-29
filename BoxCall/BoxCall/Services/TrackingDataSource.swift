import Foundation

/// The pre-release tracking number for a movie — the crowd/analyst
/// estimate of opening-weekend domestic gross in $M, plus an implied
/// volatility estimate (how wide the plausible outcome range is).
///
/// This is a SEPARATE concern from the upcoming-releases catalog
/// (MovieDataProvider). Titles come from one place; tracking numbers
/// come from another. In production, tracking is a paid feed
/// (National Research Group) or scraped from Deadline / The Numbers.
struct Tracking: Hashable {
    let openingWeekendMillions: Double
    let impliedVolPct: Double
}

protocol TrackingDataSource {
    /// Fetch tracking for a movie. May be nil when data isn't available
    /// yet (obscure indie, very early tracking window).
    func tracking(for movie: Movie) async -> Tracking?
}

// MARK: - Algorithmic (uses whatever the provider already returned)

/// Uses the estimates the MovieDataProvider already computed from
/// popularity / budget when it built the Movie. Zero-network fallback
/// so the app always has SOMETHING to price against.
final class AlgorithmicTrackingSource: TrackingDataSource {
    func tracking(for movie: Movie) async -> Tracking? {
        Tracking(
            openingWeekendMillions: movie.consensusOpeningMillions,
            impliedVolPct: movie.impliedVolPct
        )
    }
}

// MARK: - Published trade projections

/// Prices off the opening-weekend range the trades actually published.
///
/// This sits at the top of the stack because a number Deadline or
/// Variety put in print is better evidence than anything the app can
/// infer from a popularity score. The midpoint becomes the consensus and
/// the *width* of the published range becomes the implied volatility, so
/// a title the analysts agree on prices tight and a contested one prices
/// wide — which is the real information in a forecast range.
///
/// A stale projection is handed back toward the algorithmic estimate in
/// proportion to its age, so a number from three months ago stops
/// dominating a movie the week it opens.
final class TradeProjectionTrackingSource: TrackingDataSource {
    /// Below this confidence the projection is too old to lead, and the
    /// blend leans on the movie's own estimate instead.
    private let minimumConfidence = 0.15

    func tracking(for movie: Movie) async -> Tracking? {
        guard let projection = movie.tradeProjection else { return nil }
        let confidence = projection.confidence()
        guard confidence >= minimumConfidence else { return nil }

        // Blend toward the movie's standing estimate as the projection
        // ages, rather than trusting or discarding it wholesale.
        let fallback = movie.consensusOpeningMillions
        let opening = projection.midpointMillions * confidence
            + fallback * (1 - confidence)

        // Same treatment for vol: an aging range says less about how
        // uncertain the outcome still is.
        let iv = projection.impliedVolPct * confidence
            + movie.impliedVolPct * (1 - confidence)

        return Tracking(openingWeekendMillions: max(0.5, opening),
                        impliedVolPct: max(15, iv))
    }
}

// MARK: - Composite with graceful fallback

/// Tries sources in order. First one that returns a non-nil Tracking
/// wins. Guaranteed to produce a Tracking as long as the final source
/// is the algorithmic fallback.
final class CompositeTrackingSource: TrackingDataSource {
    private let sources: [TrackingDataSource]

    init(_ sources: [TrackingDataSource]) { self.sources = sources }

    func tracking(for movie: Movie) async -> Tracking? {
        for source in sources {
            if let t = await source.tracking(for: movie) { return t }
        }
        return nil
    }
}

extension Config {
    /// The tracking source stack, best evidence first: a projection the
    /// trades actually published, then the app's own estimate (from the
    /// data feed) as a guaranteed floor.
    ///
    /// Whatever this returns is then moved up or down by the sentiment
    /// engine — see `enrichedTrackingSource`.
    static var trackingSource: TrackingDataSource {
        CompositeTrackingSource([
            TradeProjectionTrackingSource(),
            AlgorithmicTrackingSource()
        ])
    }
}
