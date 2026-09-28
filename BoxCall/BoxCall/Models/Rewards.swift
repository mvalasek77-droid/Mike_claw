import Foundation
import SwiftUI

/// Trader rank. Earned only by trading profit — never bought, never
/// granted for activity — so a rank on a review means that person has
/// actually won. Based on the best total profit a trader has reached,
/// so one bad weekend doesn't take a rank away.
enum Tier: Int, Codable, CaseIterable, Comparable {
    case rookie = 0, analyst, insider, producer, studioHead, legend

    var name: String {
        switch self {
        case .rookie:     return "Rookie"
        case .analyst:    return "Analyst"
        case .insider:    return "Insider"
        case .producer:   return "Producer"
        case .studioHead: return "Studio Head"
        case .legend:     return "Legend"
        }
    }

    /// Best total profit (RC) needed to hold this rank.
    var minProfit: Double {
        switch self {
        case .rookie:     return 0
        case .analyst:    return 250
        case .insider:    return 750
        case .producer:   return 1_500
        case .studioHead: return 3_000
        case .legend:     return 7_500
        }
    }

    var color: Color {
        switch self {
        case .rookie:     return Theme.tierRookie
        case .analyst:    return Theme.tierAnalyst
        case .insider:    return Theme.tierInsider
        case .producer:   return Theme.tierProducer
        case .studioHead: return Theme.tierStudioHead
        case .legend:     return Theme.tierLegend
        }
    }

    /// Every perk listed here is shown in the app — nothing aspirational.
    var perks: [String] {
        switch self {
        case .rookie:     return ["Trade every market", "Write reviews and hot takes"]
        case .analyst:    return ["Verified checkmark next to your name"]
        case .insider:    return ["Gold username everywhere"]
        case .producer:   return ["Rank ring around your avatar"]
        case .studioHead: return ["Gold frame on your hot takes in the feed"]
        case .legend:     return ["Legend rosette beside your name on the leaderboard"]
        }
    }

    static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }

    static func forProfit(_ profit: Double) -> Tier {
        Tier.allCases.reversed().first { profit >= $0.minProfit } ?? .rookie
    }
}

struct Badge: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let blurb: String
    let earnedAt: Date

    static let catalog: [String: (String, String, String)] = [
        "first_call":    ("First Call",     "🎬", "You placed your first trade."),
        "sniper":        ("Sniper",         "🎯", "5 winning calls in a row."),
        "bomb_caller":   ("Bomb Caller",    "💥", "Nailed a put that missed by >30%."),
        "rocket":        ("Rocket",         "🚀", "Called a blockbuster that beat by >40%."),
        "contrarian":    ("Contrarian",     "🐺", "Won a trade against consensus by >20%."),
        "cinephile":     ("Cinephile",      "🎞️", "Traded 20 different movies."),
        "streak_3":      ("On a Roll",      "🔥", "3-week winning streak."),
        "streak_10":     ("Legend Building","🌟", "10-week winning streak."),
        "oracle_of":     ("Seasonal Oracle","🏆", "Season-long #1 finish.")
    ]

    static func make(_ key: String) -> Badge? {
        guard let (name, emoji, blurb) = catalog[key] else { return nil }
        return Badge(id: key, name: name, emoji: emoji, blurb: blurb, earnedAt: Date())
    }
}
