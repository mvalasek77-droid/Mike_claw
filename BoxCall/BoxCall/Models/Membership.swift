import Foundation
import SwiftUI

/// Subscription tier. Free is the default; three paid tiers unlock
/// more Reel Coins, exclusive features, and a larger weekly
/// allowance. Status (tiers, badges, leaderboard rank) is still
/// earned by winning calls, never bought.
enum Membership: String, Codable, CaseIterable, Identifiable {
    case free
    case backstage
    case producersPass
    case mogul

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .free:           return "Free"
        case .backstage:      return "Backstage"
        case .producersPass:  return "Producer's Pass"
        case .mogul:          return "Mogul"
        }
    }

    var priceString: String {
        switch self {
        case .free:           return "Free"
        case .backstage:      return "$3.99 / month"
        case .producersPass:  return "$9.99 / month"
        case .mogul:          return "$24.99 / month"
        }
    }

    /// Reel Coins granted on activation.
    var startingBonus: Double {
        switch self {
        case .free:           return 0
        case .backstage:      return 5_000
        case .producersPass:  return 15_000
        case .mogul:          return 40_000
        }
    }

    /// Reel Coins refilled every week.
    var weeklyAllowance: Double {
        switch self {
        case .free:           return 500
        case .backstage:      return 1_500
        case .producersPass:  return 4_000
        case .mogul:          return 10_000
        }
    }

    /// Simultaneous resting limit orders allowed.
    var maxLimitOrders: Int {
        switch self {
        case .free:           return 1
        case .backstage:      return 3
        case .producersPass:  return 10
        case .mogul:          return .max
        }
    }

    /// Subscribers see newly-listed movies 24h before free users.
    var hasEarlyAccess: Bool { isPaid }

    /// Subscribers get a portfolio performance dashboard.
    var hasPerformanceStats: Bool {
        switch self {
        case .free, .backstage: return false
        case .producersPass, .mogul: return true
        }
    }

    /// Only Mogul can propose custom prop markets.
    var canCreateCustomMarkets: Bool { self == .mogul }

    /// SF Symbol badge shown next to the subscriber's handle.
    var badgeIcon: String? {
        switch self {
        case .free:           return nil
        case .backstage:      return "ticket.fill"
        case .producersPass:  return "star.fill"
        case .mogul:          return "crown.fill"
        }
    }

    var perks: [String] {
        switch self {
        case .free:
            return [
                "1,000 starting Reel Coins",
                "500 RC refilled weekly, forever",
                "Full access to every market, feed, and reward"
            ]
        case .backstage:
            return [
                "5,000 RC starting bonus",
                "1,500 RC weekly allowance",
                "24-hour early access to new markets",
                "Up to 3 simultaneous limit orders",
                "Subscriber badge on your profile"
            ]
        case .producersPass:
            return [
                "15,000 RC starting bonus",
                "4,000 RC weekly allowance",
                "Portfolio performance stats",
                "Up to 10 simultaneous limit orders",
                "Everything in Backstage"
            ]
        case .mogul:
            return [
                "40,000 RC starting bonus",
                "10,000 RC weekly allowance",
                "Create custom prop markets",
                "Unlimited limit orders",
                "Everything in Producer's Pass"
            ]
        }
    }

    var accentColor: Color {
        switch self {
        case .free:           return .gray
        case .backstage:      return .blue
        case .producersPass:  return .purple
        case .mogul:          return .orange
        }
    }

    var productId: String? {
        switch self {
        case .free:           return nil
        case .backstage:      return "com.boxcall.sub.backstage.monthly"
        case .producersPass:  return "com.boxcall.sub.producers_pass.monthly"
        case .mogul:          return "com.boxcall.sub.mogul.monthly"
        }
    }

    var isPaid: Bool { self != .free }

    static let paidTiers: [Membership] = [.backstage, .producersPass, .mogul]
}
