import Foundation

/// Platform economics. Every sale runs through Apple IAP, so Apple takes its
/// commission first. Of the net proceeds, the woman keeps 85% and Auction Baby
/// keeps 15%. This split applies when a winning bid is paid — the bid amount
/// (in Gavels) represents real money the bidder already purchased via IAP.
enum Commerce {
    static let platformFeeRate: Double = 0.15
    static let womanShareRate: Double = 0.85
    static let appleCommissionRate: Double = 0.15

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    static func appleCut(on price: Double) -> Double { round2(price * appleCommissionRate) }
    static func netAfterApple(on price: Double) -> Double { round2(price - appleCut(on: price)) }

    static func womanEarning(on price: Double) -> Double { round2(netAfterApple(on: price) * womanShareRate) }
    static func platformFee(on price: Double) -> Double { round2(netAfterApple(on: price) - womanEarning(on: price)) }

    struct Breakdown {
        let gross: Double
        let appleCut: Double
        let net: Double
        let woman: Double
        let platform: Double
    }

    static func breakdown(for price: Double) -> Breakdown {
        let cut = appleCut(on: price)
        let net = round2(price - cut)
        let woman = round2(net * womanShareRate)
        return Breakdown(gross: price, appleCut: cut, net: net, woman: woman, platform: round2(net - woman))
    }

    static let feePercentLabel = "15%"
    static let sharePercentLabel = "85%"
    static let appleCutLabel = "15%"

    static let explainer = "Apple takes its App Store commission first. Of the net proceeds, you keep 85%. That's what actually reaches you after every paid date."

    /// Converts a Gavel count to its real-money equivalent using the best-value
    /// pack price. Used for earnings projections and payout calculations.
    static func gavelsToDollars(_ gavels: Int) -> Double {
        round2(Double(gavels) / 30_000.0 * 99.99)
    }

    /// Converts a dollar amount to approximate Gavel equivalent.
    static func dollarsToGavels(_ dollars: Double) -> Int {
        Int((dollars / 99.99 * 30_000).rounded())
    }
}
