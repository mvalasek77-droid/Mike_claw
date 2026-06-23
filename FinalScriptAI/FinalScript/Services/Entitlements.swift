import Foundation
import Combine

/// Pricing model and entitlement state.
///
/// The product thesis: deliver Arc Studio Pro–class screenwriting *plus* AI for
/// roughly a quarter of the price. Arc Studio Pro lists around $99/year; the
/// reference tiers below land Final Script AI Pro at $24.99/year. Real billing is
/// wired through StoreKit 2 at ship time — this type models the entitlement and
/// the upgrade surface so the UI is complete.
struct PricingTier: Identifiable, Hashable {
    let id: String
    let name: String
    let priceText: String
    let cadence: String
    let blurb: String
    let highlights: [String]
}

enum Pricing {
    /// Public comparison anchor. Arc Studio Pro ≈ $99/yr at time of writing.
    static let competitorAnnualUSD = 99.0
    static let finalScriptAnnualUSD = 24.99

    static var savingsPercent: Int {
        Int(((competitorAnnualUSD - finalScriptAnnualUSD) / competitorAnnualUSD * 100).rounded())
    }

    static let free = PricingTier(
        id: "free",
        name: "Free",
        priceText: "$0",
        cadence: "forever",
        blurb: "Everything you need to write your first script.",
        highlights: [
            "Unlimited projects",
            "Auto-formatting editor",
            "Beat board & outlining",
            "Fountain import / export",
            "10 AI assists per month"
        ]
    )

    static let pro = PricingTier(
        id: "pro.annual",
        name: "Pro",
        priceText: "$24.99",
        cadence: "per year",
        blurb: "Pro features and unlimited AI — about a quarter of Arc Studio Pro.",
        highlights: [
            "Unlimited AI co-writing & coverage",
            "Final Draft (.fdx) & PDF export",
            "Production revisions & locked pages",
            "Character bible & voice checks",
            "Title pages & dual dialogue"
        ]
    )

    static let all: [PricingTier] = [free, pro]
}

@MainActor
final class Entitlements: ObservableObject {
    @Published var isPro: Bool {
        didSet { UserDefaults.standard.set(isPro, forKey: "entitlement.pro") }
    }
    /// AI assists used this month on the free tier.
    @Published var monthlyAIUsage: Int {
        didSet { UserDefaults.standard.set(monthlyAIUsage, forKey: "entitlement.aiUsage") }
    }

    static let freeMonthlyAILimit = 10

    init() {
        isPro = UserDefaults.standard.bool(forKey: "entitlement.pro")
        monthlyAIUsage = UserDefaults.standard.integer(forKey: "entitlement.aiUsage")
        resetUsageIfNewMonth()
    }

    /// The free-tier AI cap is monthly; roll the counter over when the
    /// calendar month changes instead of letting it accumulate forever.
    private func resetUsageIfNewMonth() {
        let calendar = Calendar.current
        let currentKey = calendar.component(.year, from: .now) * 12 + calendar.component(.month, from: .now)
        let storedKey = UserDefaults.standard.integer(forKey: "entitlement.aiUsageMonthKey")
        guard storedKey != currentKey else { return }
        UserDefaults.standard.set(currentKey, forKey: "entitlement.aiUsageMonthKey")
        monthlyAIUsage = 0
    }

    var canUseAI: Bool {
        isPro || monthlyAIUsage < Self.freeMonthlyAILimit
    }

    var remainingFreeAI: Int {
        max(0, Self.freeMonthlyAILimit - monthlyAIUsage)
    }

    func recordAIUse() {
        guard !isPro else { return }
        monthlyAIUsage += 1
    }

    /// Stand-in for a successful StoreKit purchase/restore.
    func unlockPro() {
        isPro = true
        Haptics.success()
    }
}
