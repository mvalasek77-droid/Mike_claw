import Foundation

/// Rolling support/resistance for a single contract, derived from
/// recent price history. Support ≈ the level below which buyers keep
/// stepping in; resistance ≈ the level above which sellers keep hitting.
struct SRLevel: Hashable {
    let support: Double
    let resistance: Double
    let mid: Double

    var band: Double { max(0.01, resistance - support) }
}

/// Background traders that behave like real market makers:
///   - Buy when price approaches support (adds a floor)
///   - Sell when price approaches resistance (adds a ceiling)
///   - Aggression scales with distance INTO the level
/// Result: the tape mean-reverts inside a band instead of random-walking,
/// which is what makes real options charts look "chart-shaped."
enum MarketMaker {
    /// Rolling window used to compute S/R (in tick counts).
    static let window: Int = 30
    /// Percentiles for S/R inside the window.
    static let supportPercentile: Double    = 0.20
    static let resistancePercentile: Double = 0.80
    /// Fraction of the band width that counts as "at the level".
    static let touchZone: Double = 0.15

    /// Compute S/R from a price series. Returns nil if too little history.
    static func levels(from points: [PricePoint]) -> SRLevel? {
        guard points.count >= 8 else { return nil }
        let recent = points.suffix(window).map(\.mark).sorted()
        let s = percentile(sorted: recent, p: supportPercentile)
        let r = percentile(sorted: recent, p: resistancePercentile)
        // Ensure resistance is strictly above support even if the tape
        // has been flat — otherwise MM logic can't compute a band.
        let adjustedR = max(r, s * 1.02)
        return SRLevel(support: s, resistance: adjustedR, mid: (s + adjustedR) / 2)
    }

    /// One tick of MM behavior. Returns the demand deltas the caller
    /// should apply (positive = MM buys, negative = MM sells).
    ///
    /// - `mark`: current mark for this contract
    /// - `level`: computed S/R band
    /// Aggression scales with how deep the price is INTO the zone.
    static func demandDelta(mark: Double, level: SRLevel) -> Double {
        let zone = level.band * touchZone

        if mark <= level.support + zone {
            // Below or near support → MM steps in as a buyer.
            let depth = max(0, (level.support + zone - mark) / max(0.01, zone))
            let size = 2.0 + 6.0 * min(1.5, depth)   // 2-11 units
            return +size
        }
        if mark >= level.resistance - zone {
            // Above or near resistance → MM steps in as a seller.
            let depth = max(0, (mark - (level.resistance - zone)) / max(0.01, zone))
            let size = 2.0 + 6.0 * min(1.5, depth)
            return -size
        }
        // Inside the band — small drift noise so the tape stays alive.
        return Double.random(in: -1.5...1.5)
    }

    // MARK: - Percentile helper

    private static func percentile(sorted values: [Double], p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let clamped = min(max(p, 0), 1)
        let position = clamped * Double(values.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return values[lower] }
        let weight = position - Double(lower)
        return values[lower] * (1 - weight) + values[upper] * weight
    }
}
