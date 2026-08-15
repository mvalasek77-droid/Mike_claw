import Foundation

struct User: Codable, Hashable {
    var handle: String
    var reelCoins: Double
    var lifetimePnL: Double
    var weeklyAllowance: Double
    var lastAllowanceAt: Date

    // Reputation
    var xp: Int
    var currentStreakWeeks: Int
    var longestStreakWeeks: Int
    var followerCount: Int
    var followingHandles: Set<String>
    var badges: [Badge]
    var trophies: [String]        // e.g. ["Oracle · Summer 2026"]
    var bio: String

    var tier: Tier { Tier.forXP(xp) }

    /// XP progress inside the current tier (0.0 - 1.0).
    var tierProgress: Double {
        let current = tier
        let next = Tier(rawValue: current.rawValue + 1) ?? current
        guard next != current else { return 1.0 }
        let base = current.minXP
        let span = next.minXP - base
        return min(1.0, max(0.0, Double(xp - base) / Double(span)))
    }
}

struct LeaderboardEntry: Identifiable, Codable, Hashable {
    let id: String        // handle
    let handle: String
    let tier: Tier
    let reelCoins: Double
    let weeklyPnL: Double
    let winRate: Double
    let isCurrentUser: Bool
}
