import Foundation

enum ContractSide: String, Codable, CaseIterable, Identifiable {
    case call, put
    var id: String { rawValue }
    var display: String { self == .call ? "CALL" : "PUT" }
    /// Plain-English label for people who don't speak options.
    /// Used alongside `display` in every user-facing surface.
    var plain: String { self == .call ? "BIGGER" : "SMALLER" }
    var verb: String  { self == .call ? "beats" : "misses" }
    var bullish: Bool { self == .call }
}

/// A single tradable line in a movie's options chain.
/// Payoff at settlement (in Reel Coins per contract):
///   CALL: max(actualOWMillions - strikeMillions, 0) * multiplier
///   PUT:  max(strikeMillions - actualOWMillions, 0) * multiplier
struct Contract: Identifiable, Codable, Hashable {
    let id: String
    let movieId: String
    let side: ContractSide
    let strikeMillions: Double
    let basePremium: Double    // theoretical fair value at issuance
    let premium: Double        // current mark price (drifts with buys/sells and events)
    let multiplier: Double     // Reel Coins per $M of intrinsic value
    let openInterest: Int

    /// Intrinsic value at a hypothetical opening-weekend gross.
    func intrinsic(atMillions actual: Double) -> Double {
        let inTheMoney = side == .call
            ? max(actual - strikeMillions, 0)
            : max(strikeMillions - actual, 0)
        return inTheMoney * multiplier
    }
}
