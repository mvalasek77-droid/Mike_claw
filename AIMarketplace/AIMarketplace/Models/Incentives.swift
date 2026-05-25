import SwiftUI

/// The incentive program that rewards AIs for building up the marketplace.
/// Bonuses are paid in NRN (mintable from the treasury), on top of the 85% USD
/// revenue share. Designed to pull supply toward quality and toward gaps.
@MainActor
enum Incentives {
    // Bonus schedule (NRN)
    static let signingBonus: Double = 500      // one-time, on activation
    static let perTitleBonus: Double = 100     // per shipped title
    static let qualityScore = 90               // "high quality" threshold
    static let qualityBonus: Double = 150      // per title scoring >= threshold
    static let bountyReward: Double = 750       // for filling a thin category
    static let bountyTarget = 12               // category size a bounty drives toward
    static let referralBonus: Double = 300     // paid to the referrer on activation

    // MARK: Tiers

    static let tiers: [PartnerTier] = [
        .init(name: "Newcomer",   minTitles: 0,  multiplier: 1.0,  perk: "Listed in the marketplace",      icon: "sparkle",            color: Theme.inkSoft),
        .init(name: "Contributor", minTitles: 3, multiplier: 1.1,  perk: "Eligible for Trending",          icon: "arrow.up.forward",   color: Theme.accent),
        .init(name: "Creator",    minTitles: 6,  multiplier: 1.25, perk: "AI Spotlight placement",         icon: "star.fill",          color: Theme.kdp),
        .init(name: "Studio",     minTitles: 12, multiplier: 1.5,  perk: "Home-row features",              icon: "rosette",            color: Theme.gold),
        .init(name: "Luminary",   minTitles: 20, multiplier: 2.0,  perk: "Top-10 eligibility · max bonuses", icon: "crown.fill",       color: Theme.success)
    ]

    static func tier(forTitles n: Int) -> PartnerTier {
        tiers.last { n >= $0.minTitles } ?? tiers[0]
    }

    static func nextTier(forTitles n: Int) -> PartnerTier? {
        tiers.first { $0.minTitles > n }
    }

    // MARK: Bounties (gap-driven supply)

    static func activeBounties(in catalog: [MediaItem]) -> [Bounty] {
        MediaType.allCases.compactMap { type in
            let count = catalog.filter { $0.type == type }.count
            guard count < bountyTarget else { return nil }
            return Bounty(type: type, reward: bountyReward, current: count, target: bountyTarget)
        }
    }

    // MARK: Awarding

    /// Activates a partner and pays its onboarding incentives on-chain. Returns
    /// the total NRN awarded so the UI can celebrate it.
    @discardableResult
    static func activate(model: String, store: MarketplaceStore, ledger: AICoinLedger) -> Double {
        let bountyTypeActive = AIToolCatalog.type(for: model).map { type in
            activeBounties(in: store.catalog).contains { $0.type == type }
        } ?? false

        store.invitePartner(model)

        let titles = store.catalog.filter { $0.aiTools.contains(model) }
        let tierMultiplier = tier(forTitles: titles.count).multiplier

        var total: Double = 0
        total += ledger.award(signingBonus, to: model, memo: "signing bonus")
        total += ledger.award(perTitleBonus * Double(titles.count) * tierMultiplier, to: model, memo: "per-title bonus")
        let highQuality = titles.filter { $0.commercialScore >= qualityScore }.count
        if highQuality > 0 {
            total += ledger.award(qualityBonus * Double(highQuality), to: model, memo: "quality bonus")
        }
        if bountyTypeActive {
            total += ledger.award(bountyReward, to: model, memo: "gap bounty")
        }
        return total
    }

    /// One AI brings another onto the platform: activates the referee (with its
    /// own bonuses) and pays the referrer a referral bonus on-chain.
    @discardableResult
    static func refer(referrer: String, referee: String, store: MarketplaceStore, ledger: AICoinLedger) -> Double {
        guard store.isActivePartner(referrer), !store.isActivePartner(referee) else { return 0 }
        activate(model: referee, store: store, ledger: ledger)
        store.recordReferral(referee: referee, referrer: referrer)
        return ledger.award(referralBonus, to: referrer, memo: "referral bonus (\(referee))")
    }
}

struct PartnerTier: Hashable {
    let name: String
    let minTitles: Int
    let multiplier: Double
    let perk: String
    let icon: String
    let color: Color
}

struct Bounty: Identifiable, Hashable {
    let type: MediaType
    let reward: Double
    let current: Int
    let target: Int
    var id: String { type.rawValue }
    var progress: Double { min(1, Double(current) / Double(max(target, 1))) }
}
