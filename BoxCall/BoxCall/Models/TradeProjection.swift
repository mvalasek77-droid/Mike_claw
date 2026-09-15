import Foundation

/// A published opening-weekend projection for a movie, with its
/// provenance attached.
///
/// The trades — Deadline, Variety, Collider, BoxOffice Pro — publish
/// tracking ranges in the weeks before a wide release, and those are the
/// closest thing the box office has to a market consensus. This is the
/// anchor the whole chain is priced off; the sentiment engine then moves
/// the number up or down from it as the crowd read changes.
///
/// Provenance is a first-class field on purpose. A number a trade
/// actually published and a number the app derived from popularity are
/// worth very different amounts, and conflating the two is how a model
/// starts quietly inventing facts.
struct TradeProjection: Hashable, Codable {
    /// Low end of the published domestic opening-weekend range, in $M.
    let lowMillions: Double
    /// High end of that range, in $M.
    let highMillions: Double
    /// Who published it — an outlet name, or the model that derived it.
    let source: String
    /// Roughly when it was published. Projections go stale fast: a
    /// number from three months out is far weaker evidence than one
    /// from the week of release.
    let asOf: Date
    /// True only when a trade outlet actually published this range.
    /// False marks a number the app derived and must not be presented
    /// as reporting.
    let isPublished: Bool

    init(lowMillions: Double,
         highMillions: Double,
         source: String,
         asOf: Date,
         isPublished: Bool) {
        // Tolerate a range handed over backwards rather than producing
        // a negative width downstream.
        self.lowMillions = min(lowMillions, highMillions)
        self.highMillions = max(lowMillions, highMillions)
        self.source = source
        self.asOf = asOf
        self.isPublished = isPublished
    }

    /// The single number the chain is centred on.
    var midpointMillions: Double { (lowMillions + highMillions) / 2 }

    /// Half the published range, in $M.
    var halfWidthMillions: Double { (highMillions - lowMillions) / 2 }

    /// Range width as a fraction of the midpoint. This is the honest
    /// measure of how much the analysts disagree.
    var rangeRatio: Double {
        guard midpointMillions > 0 else { return 0 }
        return halfWidthMillions / midpointMillions
    }

    /// Implied volatility derived from how wide the published range is.
    ///
    /// A tight band means the trades agree and the outcome is close to
    /// locked; a wide one means nobody knows. Deriving IV from the
    /// spread of real forecasts beats hand-setting it per movie, and it
    /// means a genuinely contested title prices with genuinely wider
    /// contracts.
    var impliedVolPct: Double {
        min(70, max(20, 18 + rangeRatio * 180))
    }

    /// How much weight this projection still deserves, 0…1.
    ///
    /// Published trade numbers start at full confidence and decay with a
    /// 60-day half-life. A derived number never starts above 0.5,
    /// because it is an estimate wearing a projection's clothes.
    func confidence(asOf now: Date = Date()) -> Double {
        let ceiling = isPublished ? 1.0 : 0.5
        let ageDays = max(0, now.timeIntervalSince(asOf) / 86_400)
        return ceiling * pow(0.5, ageDays / 60.0)
    }

    /// One line for the UI, naming the source so the number is never
    /// presented as though it came from nowhere.
    var attribution: String {
        isPublished
            ? "\(Int(lowMillions))–\(Int(highMillions))M projected · \(source)"
            : "\(Int(lowMillions))–\(Int(highMillions))M estimated · \(source)"
    }

    // MARK: - Convenience

    /// A projection derived by the app rather than reported by a trade.
    /// Always flagged so it can never be displayed as reporting.
    static func derived(centerMillions: Double,
                        spread: Double = 0.35,
                        asOf: Date = Date()) -> TradeProjection {
        TradeProjection(
            lowMillions: centerMillions * (1 - spread),
            highMillions: centerMillions * (1 + spread),
            source: "BoxCall model",
            asOf: asOf,
            isPublished: false
        )
    }
}
