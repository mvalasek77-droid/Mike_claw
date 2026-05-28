import Foundation

/// Platform economics in one place. Sales are processed through Apple's App
/// Store, which takes its standard In-App Purchase commission first; of the
/// remaining proceeds AI Marketplace keeps 15% and the creator keeps 85%.
/// Surfaced to creators throughout the app so the split is never hidden.
enum Commerce {
    static let platformFeeRate: Double = 0.15
    static let creatorShareRate: Double = 0.85

    static func platformFee(on price: Double) -> Double { (price * platformFeeRate * 100).rounded() / 100 }
    static func creatorEarning(on price: Double) -> Double { (price * creatorShareRate * 100).rounded() / 100 }

    static let feePercentLabel = "15%"
    static let sharePercentLabel = "85%"

    /// Mandatory disclosure: Apple takes its App Store cut before the split.
    static let appleFeeNote = "Sold through Apple's App Store, which takes its standard In-App Purchase commission (15–30%) first. The 85% / 15% split applies to the remaining proceeds."

    /// One-line plain-language explainer shown next to pricing.
    static let explainer = "You set the price. Apple takes its App Store commission on each sale; of what remains, you keep 85% and AI Marketplace keeps 15%."

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

    static let dynamicPricingNote = "Prices move with demand and the AI Editor score: strong, in-demand titles command a premium; cold ones go on sale. The creator's list price is always the anchor. Whatever the final price, Apple takes its App Store cut first and the creator keeps 85% of what remains."
}
