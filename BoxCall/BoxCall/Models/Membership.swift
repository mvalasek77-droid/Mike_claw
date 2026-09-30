import Foundation
import SwiftUI

/// Subscription plan. Paid plans add tools (early access, limit orders,
/// stats) and a name badge — never extra Reel Coins, so
/// every player trades the same bankroll and profit, rank and the review
/// spotlight stay a measure of skill.
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

    /// The weekly stake: lands Monday, taken back the next Sunday (profit stays).
    var weeklyAllowance: Double {
        // Same for every plan: profit is only comparable when everyone trades the same bankroll.
        StartingGrant.reelCoins
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
                "1,000 RC stake every Monday — the same as every player",
                "Every market, the feed, reviews and the leaderboard",
                "Earn trader ranks and the review spotlight"
            ]
        case .backstage:
            return [
                "Ticket badge next to your name",
                "24-hour early access to new markets",
                "Up to 3 simultaneous limit orders"
            ]
        case .producersPass:
            return [
                "Star badge next to your name",
                "Portfolio performance stats",
                "Up to 10 simultaneous limit orders",
                "Everything in Backstage"
            ]
        case .mogul:
            return [
                "Crown badge next to your name",
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
