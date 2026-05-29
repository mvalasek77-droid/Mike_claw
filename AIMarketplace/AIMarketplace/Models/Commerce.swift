import Foundation

/// Platform economics in one place. Every sale runs through Apple's In-App
/// Purchase, so **Apple takes its commission first**. Of what's left (the net
/// proceeds), the creator keeps 85% and AI Marketplace keeps 15%.
enum Commerce {
    static let platformFeeRate: Double = 0.15
    static let creatorShareRate: Double = 0.85
    /// Apple's App Store commission. 15% under the Small Business Program
    /// (revenue under $1M/yr — what this marketplace qualifies for), else 30%.
    static let appleCommissionRate: Double = 0.15

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    static func appleCut(on price: Double) -> Double { round2(price * appleCommissionRate) }
    static func netAfterApple(on price: Double) -> Double { round2(price - appleCut(on: price)) }

    /// What the creator actually receives: 85% of the net after Apple's cut.
    static func creatorEarning(on price: Double) -> Double { round2(netAfterApple(on: price) * creatorShareRate) }
    /// AI Marketplace's share: 15% of the net after Apple's cut.
    static func platformFee(on price: Double) -> Double { round2(netAfterApple(on: price) - creatorEarning(on: price)) }

    /// Full per-sale split for display in the pricing UI.
    struct Breakdown {
        let gross: Double
        let appleCut: Double
        let net: Double
        let creator: Double
        let marketplace: Double
    }

    static func breakdown(for price: Double) -> Breakdown {
        let cut = appleCut(on: price)
        let net = round2(price - cut)
        let creator = round2(net * creatorShareRate)
        return Breakdown(gross: price, appleCut: cut, net: net, creator: creator, marketplace: round2(net - creator))
    }

    static let feePercentLabel = "15%"
    static let sharePercentLabel = "85%"
    static let appleCutLabel = "15%"

    /// Plain-language pricing explainer shown next to pricing.
    static let explainer = "You set the price. Apple takes its App Store commission first; of the net proceeds you keep 85%. That 85% is what actually reaches you."

    // MARK: - Dynamic pricing

    /// Transparent demand-based pricing. The creator's list price is the anchor;
    /// the marketplace nudges it within ±25% using the AI Editor score (quality
    /// commands a premium) and recent demand (`0` cold … `0.5` neutral … `1`
    /// hottest seller). Always clamped to the allowed range.
    static func dynamicPrice(list: Double, score: Int, demand: Double) -> Double {
        let scoreAdj = Double(score - 90) / 100.0 * 1.2          // 90→0, 100→+0.12, 80→−0.12
        let demandAdj = (max(0, min(1, demand)) - 0.5) * 0.30    // 0.5→0, 1→+0.15, 0→−0.15
        let factor = max(0.75, min(1.25, 1 + scoreAdj + demandAdj))
        let price = max(0.99, min(19.99, list * factor))
        return (price * 100).rounded() / 100
    }

    static let dynamicPricingNote = "Prices move with demand and the AI Editor score: strong, in-demand titles command a premium; cold ones go on sale. Your list price is always the anchor. Whatever the final price, you keep 85% of the net proceeds after Apple's commission."
}