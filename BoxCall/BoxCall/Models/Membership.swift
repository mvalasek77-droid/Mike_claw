import Foundation
import SwiftUI

/// Subscription tier. Free is the default; three paid tiers unlock
/// more Reel Coins (both a one-time starting bonus and a larger
/// weekly allowance). Everything else in the app is identical for
/// free and paid users — no gameplay is gated. This keeps status
/// (tiers, badges, leaderboard rank) earned rather than bought.
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
                "Ad-free experience",
                "Extended news ticker (last 20 events / movie)"
            ]
        case .producersPass:
            return [
                "15,000 RC starting bonus",
                "4,000 RC weekly allowance",
                "Advanced analytics: IV history, demand heatmap",
                "Priority contest slots on Monday tournaments",
                "Producer's Pass badge on your profile"
            ]
        case .mogul:
            return [
                "40,000 RC starting bonus",
                "10,000 RC weekly allowance",
                "Create custom markets (\"Villeneuve's next opens above $50M\")",
                "Pin one post to any movie page for 24h / week",
                "Exclusive gold Mogul frame on your avatar",
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
