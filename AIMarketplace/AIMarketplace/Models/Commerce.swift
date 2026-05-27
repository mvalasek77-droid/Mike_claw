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
}
