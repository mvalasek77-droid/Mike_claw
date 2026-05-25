import Foundation

/// Platform economics in one place. AI Marketplace takes a 15% service fee on
/// every sale; the creator keeps 85%. Surfaced to creators throughout the
/// publishing flow and on the earnings dashboard so the split is never hidden.
enum Commerce {
    static let platformFeeRate: Double = 0.15
    static let creatorShareRate: Double = 0.85

    static func platformFee(on price: Double) -> Double { (price * platformFeeRate * 100).rounded() / 100 }
    static func creatorEarning(on price: Double) -> Double { (price * creatorShareRate * 100).rounded() / 100 }

    static let feePercentLabel = "15%"
    static let sharePercentLabel = "85%"

    /// One-line plain-language explainer shown next to pricing.
    static let explainer = "You set the price. On every sale AI Marketplace keeps a 15% service fee and pays you the remaining 85%."
}
