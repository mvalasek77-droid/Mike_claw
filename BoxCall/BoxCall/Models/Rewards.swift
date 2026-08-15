import Foundation
import SwiftUI

enum Tier: Int, Codable, CaseIterable, Comparable {
    case rookie = 0, analyst, insider, producer, studioHead, oracle

    var name: String {
        switch self {
        case .rookie:     return "Rookie"
        case .analyst:    return "Analyst"
        case .insider:    return "Insider"
        case .producer:   return "Producer"
        case .studioHead: return "Studio Head"
        case .oracle:     return "Oracle"
        }
    }

    var minXP: Int {
        switch self {
        case .rookie:     return 0
        case .analyst:    return 500
        case .insider:    return 2_000
        case .producer:   return 5_000
        case .studioHead: return 15_000
        case .oracle:     return 50_000
        }
    }

    var color: Color {
        switch self {
        case .rookie:     return .gray
        case .analyst:    return .blue
        case .insider:    return .yellow
        case .producer:   return .purple
        case .studioHead: return .pink
        case .oracle:     return .orange
        }
    }

    var perks: [String] {
        switch self {
        case .rookie:     return ["Trade the chain", "React to public calls"]
        case .analyst:    return ["Verified checkmark", "Post to the public feed"]
        case .insider:    return ["Gold username", "Boost one call/week to top of a movie page"]
        case .producer:   return ["Create custom markets", "Animated avatar frame"]
        case .studioHead: return ["Pin any post for 24h", "Custom victory animation"]
        case .oracle:     return ["Seasonal Oracle title", "Quoted on the home feed"]
        }
    }

    static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }

    static func forXP(_ xp: Int) -> Tier {
        Tier.allCases.reversed().first { xp >= $0.minXP } ?? .rookie
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
