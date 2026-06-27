import Foundation

/// The bidder's floor filters. Age and "hide copycats" are free; the advanced
/// filters (verified-only, interest matching) are a Pass perk — the standard
/// premium lever in modern dating apps.
struct FilterPreferences: Codable, Equatable {
    var minAge: Int = 18
    var maxAge: Int = 60
    var hideCopycats: Bool = false

    // Premium (Pass-gated)
    var verifiedOnly: Bool = false
    var interests: Set<String> = []

    /// Count of filters narrowing the feed (for the toolbar badge).
    var activeCount: Int {
        var n = 0
        if minAge > 18 || maxAge < 60 { n += 1 }
        if hideCopycats { n += 1 }
        if verifiedOnly { n += 1 }
        if !interests.isEmpty { n += 1 }
        return n
    }

    /// Whether a profile passes the current filters.
    func matches(_ p: Profile) -> Bool {
        guard p.age >= minAge, p.age <= maxAge else { return false }
        if hideCopycats, p.isCopycat { return false }
        if verifiedOnly, !p.verified { return false }
        if !interests.isEmpty, interests.isDisjoint(with: Set(p.interests)) { return false }
        return true
    }

    static let interestPool = ["Art", "Travel", "Food", "Fitness", "Music", "Startups",
                               "Wine", "Film", "Reading", "Dogs", "Nightlife", "Design"]
}
