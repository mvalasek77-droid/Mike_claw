import Foundation

struct Movie: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let studio: String
    let releaseDate: Date
    let posterEmoji: String            // fallback identifier
    let posterURL: String?             // real poster from TMDB / provider
    let tagline: String
    let consensusOpeningMillions: Double
    let impliedVolPct: Double
    let genre: String
    let addedAt: Date                  // for "NEW" badge on Slate

    // Rich facts (nil when the provider doesn't know them)
    let director: String?
    let cast: [String]
    let synopsis: String?
    /// Search query used by the YouTube trailer link.
    /// Defaults to "<title> official trailer".
    let trailerQuery: String?
    /// Rotten Tomatoes-style critic score 0-100 if known pre-release.
    let criticScore: Int?
    /// Published opening-weekend projection from the trades, when one
    /// exists. This is the anchor the chain is priced off; sentiment
    /// then moves the number up or down from here.
    let tradeProjection: TradeProjection?

    init(
        id: String,
        title: String,
        studio: String,
        releaseDate: Date,
        posterEmoji: String,
        posterURL: String? = nil,
        tagline: String,
        consensusOpeningMillions: Double,
        impliedVolPct: Double,
        genre: String,
        addedAt: Date = Date(),
        director: String? = nil,
        cast: [String] = [],
        synopsis: String? = nil,
        trailerQuery: String? = nil,
        criticScore: Int? = nil,
        tradeProjection: TradeProjection? = nil
    ) {
        self.id = id
        self.title = title
        self.studio = studio
        self.releaseDate = releaseDate
        self.posterEmoji = posterEmoji
        self.posterURL = posterURL
        self.tagline = tagline
        self.consensusOpeningMillions = consensusOpeningMillions
        self.impliedVolPct = impliedVolPct
        self.genre = genre
        self.addedAt = addedAt
        self.director = director
        self.cast = cast
        self.synopsis = synopsis
        self.trailerQuery = trailerQuery
        self.criticScore = criticScore
        self.tradeProjection = tradeProjection
    }

    var daysToRelease: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: releaseDate)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// Trading closes at the START of Sunday of opening weekend (release
    /// is a Friday). Studios publish opening-weekend ESTIMATES Sunday
    /// morning and finals Monday afternoon — leaving trading open until
    /// Monday (the old releaseDate+3d rule) let users trade with the
    /// result already on Box Office Mojo. Sunday-start guarantees the
    /// book is closed before any weekend figure is public.
    var isSettled: Bool {
        tradingClosedAt < Date()
    }

    /// The moment trading halts on this movie: start of the SUNDAY that
    /// ends opening weekend. Wide releases are usually Fridays (+2 days)
    /// but holiday titles open Wednesdays (Thanksgiving, Christmas) —
    /// the weekend figure still publishes the Sunday after release, so
    /// scan forward to that Sunday rather than assuming a Friday open.
    /// Positions remain open until `settlementDate` below; only NEW
    /// trades are blocked.
    var tradingClosedAt: Date {
        let cal = Calendar(identifier: .gregorian)
        let release = cal.startOfDay(for: releaseDate)
        // Weekday 1 is always Sunday in the gregorian 7-day week.
        if let closed = cal.nextDate(
            after: release,
            matching: DateComponents(weekday: 1),
            matchingPolicy: .nextTime
        ) {
            return cal.startOfDay(for: closed)
        }
        return releaseDate.addingTimeInterval(2 * 86400)
    }

    /// When positions actually settle (pay out): end of the same
    /// Sunday that closes trading — the published weekend figure
    /// (estimates Sunday ~9am–noon ET, finals Monday) is what strikes
    /// the positions. The data pipeline publishes every 3 hours and
    /// actuals are cumulative, so the number is there by the time the
    /// app next checks; a 48h grace inside SettlementService covers a
    /// dead pipeline without letting positions dangle forever.
    var settlementDate: Date {
        tradingClosedAt.addingTimeInterval(24 * 3600)
    }

    var isNewlyAdded: Bool {
        Date().timeIntervalSince(addedAt) < 48 * 3600
    }

    /// Opening-day Friday midnight local, for the countdown.
    var opensAt: Date {
        Calendar.current.startOfDay(for: releaseDate)
    }

    var resolvedTrailerQuery: String {
        trailerQuery ?? "\(title) official trailer"
    }
}
