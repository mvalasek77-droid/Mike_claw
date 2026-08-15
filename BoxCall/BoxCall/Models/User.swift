import Foundation

struct User: Codable, Hashable {
    var handle: String
    var reelCoins: Double
    var lifetimePnL: Double
    var weeklyAllowance: Double
    var lastAllowanceAt: Date
}

struct LeaderboardEntry: Identifiable, Codable, Hashable {
    let id: String        // handle
    let handle: String
    let reelCoins: Double
    let weeklyPnL: Double
    let winRate: Double
    let isCurrentUser: Bool
}
