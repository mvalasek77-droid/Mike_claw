import Foundation

/// Owns the *initial* pricing of a new options chain.
///
/// Given a movie + its tracking (consensus opening + implied vol),
/// PriceSetter emits a five-strike-each-side chain with theoretical
/// premiums. Once the chain is live, MarketService's demand-driven
/// market takes over and the mark drifts from these anchors.
///
/// Kept as a pure struct with no dependencies so it's trivially
/// testable and swappable. Formula documented below.
struct PriceSetter {
    /// Strikes = center ± {2, 1, 0, 1, 2} × step.
    /// Step = 10% of consensus, rounded, floored at 1.
    var strikeOffsets: [Int] = [-2, -1, 0, 1, 2]
    /// Reel Coins per $1M of intrinsic value per contract.
    var multiplier: Double = 1.0
    /// Minimum premium so nothing prices to zero.
    var floorPremium: Double = 0.25
    /// Tuning constants for the time-value curve.
    var moneynessDecay: Double = 1.8   // higher = OTM prems drop off faster
    var timeValueCoeff: Double = 0.5   // scales overall time value

    /// Build a full chain of Contracts for a movie.
    ///
    /// Formula per strike per side:
    ///   intrinsic  = max(consensus - K, 0)  for Call
    ///                max(K - consensus, 0)  for Put
    ///   moneyness  = |consensus - K| / consensus
    ///   timeValue  = consensus × IV × √(DTE/30) × exp(-moneyness × decay) × coeff
    ///   premium    = max(floor, intrinsic + timeValue)
    ///
    /// This is a plain-English Black-Scholes cousin: intrinsic value
    /// plus a time-value bump that decays with distance from consensus
    /// and grows with volatility and time-to-expiry.
    func chain(for movie: Movie, tracking: Tracking) -> [Contract] {
        let center = tracking.openingWeekendMillions
        let step = max(1.0, (center * 0.10).rounded())
        let strikes = strikeOffsets.map { (center + Double($0) * step).rounded() }
        let iv = tracking.impliedVolPct / 100.0
        let dte = max(1, movie.daysToRelease)

        var out: [Contract] = []
        for side in ContractSide.allCases {
            for k in strikes {
                let intrinsic = side == .call
                    ? max(center - k, 0)
                    : max(k - center, 0)
                let moneyness = abs(center - k) / max(1, center)
                let timeValue = center * iv * sqrt(Double(dte) / 30.0)
                              * exp(-moneyness * moneynessDecay) * timeValueCoeff
                let fair = max(floorPremium, intrinsic + timeValue)
                let rounded = (fair * 100).rounded() / 100
                out.append(.init(
                    id: "\(movie.id)_\(side.rawValue)_\(Int(k))",
                    movieId: movie.id,
                    side: side,
                    strikeMillions: k,
                    basePremium: rounded,
                    premium: rounded,
                    multiplier: multiplier,
                    openInterest: Int.random(in: 40...900)
                ))
            }
        }
        return out.sorted {
            ($0.side.rawValue, $0.strikeMillions) < ($1.side.rawValue, $1.strikeMillions)
        }
    }
}
