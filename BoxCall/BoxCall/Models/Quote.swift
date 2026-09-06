import Foundation

/// A two-sided market: what the desk will pay (bid) and what it will
/// sell at (ask), with the size standing at each level.
///
/// Everything downstream of the desk speaks in Quotes. The single
/// "mark" the rest of the app still displays is just `mid`.
struct Quote: Hashable, Codable {
    let bid: Double
    let ask: Double
    let bidSize: Int
    let askSize: Int

    init(bid: Double, ask: Double, bidSize: Int, askSize: Int) {
        self.bid = bid
        self.ask = ask
        self.bidSize = max(0, bidSize)
        self.askSize = max(0, askSize)
    }

    /// The printed mark — halfway between the two sides.
    var mid: Double { (bid + ask) / 2 }

    /// Absolute width of the market, in Reel Coins.
    var spread: Double { max(0, ask - bid) }

    /// Width as a fraction of mid. This is the number traders actually
    /// compare across contracts — 0.04 means a 4% wide market.
    var spreadPct: Double { mid > 0 ? spread / mid : 0 }

    /// Order-book imbalance in [-1, +1]. Positive means more size is
    /// resting on the bid (buyers outweigh sellers), negative the
    /// reverse. This is what makes the ladder feel alive.
    var imbalance: Double {
        let total = Double(bidSize + askSize)
        guard total > 0 else { return 0 }
        return (Double(bidSize) - Double(askSize)) / total
    }

    /// A market is crossed when the bid is at or above the ask — an
    /// impossible state that means two agents disagree so hard they
    /// would trade with each other. The desk resolves these before
    /// publishing, but the check stays public for tests.
    var isCrossed: Bool { bid >= ask }

    /// Quality label for the UI. Tight markets are cheap to cross;
    /// wide ones punish impatience.
    var liquidityGrade: LiquidityGrade {
        switch spreadPct {
        case ..<0.02:  return .deep
        case ..<0.05:  return .healthy
        case ..<0.10:  return .thin
        default:       return .fractured
        }
    }

    /// Rounds both sides to whole cents so the ladder never renders
    /// floating-point dust.
    func rounded() -> Quote {
        Quote(bid: (bid * 100).rounded() / 100,
              ask: (ask * 100).rounded() / 100,
              bidSize: bidSize, askSize: askSize)
    }

    /// The price a taker actually pays or receives.
    func executionPrice(isBuy: Bool) -> Double { isBuy ? ask : bid }

    static let empty = Quote(bid: 0, ask: 0, bidSize: 0, askSize: 0)
}

/// How good the market is right now, derived from spread width.
enum LiquidityGrade: String, Codable, CaseIterable {
    case deep, healthy, thin, fractured

    var label: String {
        switch self {
        case .deep:      return "Deep"
        case .healthy:   return "Healthy"
        case .thin:      return "Thin"
        case .fractured: return "Fractured"
        }
    }

    /// One line the UI shows under the spread meter.
    var blurb: String {
        switch self {
        case .deep:
            return "Agents agree. Cheap to get in and out."
        case .healthy:
            return "Normal two-sided market."
        case .thin:
            return "Agents are pulling back. Crossing costs more."
        case .fractured:
            return "The desk disagrees violently. Trade small."
        }
    }
}
