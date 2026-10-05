import Foundation

struct User: Codable, Hashable {
    var handle: String
    var reelCoins: Double
    var lifetimePnL: Double
    var weeklyAllowance: Double
    var lastAllowanceAt: Date
    /// The part of the balance that is this week's stake (taken back on Sunday).
    var weeklyStake: Double?
    var lastResetAt: Date?
    /// Stake still riding on trades at the last reset, repaid from their proceeds.
    var stakeOwed: Double?
    var lastStreakBumpAt: Date?
    /// Season the app last checked, so the Oracle crown is awarded once at rollover.
    var lastSeasonChecked: String?

    // Reputation (earned, not bought)
    /// Highest total profit ever reached — sets the trader rank.
    var bestProfit: Double?
    var currentStreakWeeks: Int
    var longestStreakWeeks: Int
    var followingHandles: Set<String>
    var badges: [Badge]
    var trophies: [String]        // e.g. ["Oracle · Summer 2026"]
    var bio: String

    // Subscription
    var membership: Membership

    // Identity (nil when browsing as a guest)
    var appleUserId: String?

    var rankProfit: Double { max(bestProfit ?? 0, lifetimePnL) }

    var tier: Tier { Tier.forProfit(rankProfit) }

    /// Progress from the current rank to the next (0.0 - 1.0).
    var tierProgress: Double {
        let current = tier
        guard let next = Tier(rawValue: current.rawValue + 1) else { return 1.0 }
        let span = next.minProfit - current.minProfit
        return min(1.0, max(0.0, (rankProfit - current.minProfit) / span))
    }
}

struct LeaderboardEntry: Identifiable, Codable, Hashable {
    let id: String
    let handle: String
    let tier: Tier
    /// Total realized trading profit — the ranking metric. The weekly
    /// stake never counts, and subscriptions never add coins.
    let profit: Double
    let weeklyPnL: Double
    let winRate: Double
    let isCurrentUser: Bool
}

/// Every account starts here. Enforced at creation — no promo codes,
/// no way for a free user to start with more than another
/// free user. Paid tiers layer on top via Membership.
enum StartingGrant {
    static let reelCoins: Double = 1_000
}
