import Foundation

/// The bidder's floor filters. Age range is free; the advanced filters
/// (verified-only, interest matching) are a Pass perk.
struct FilterPreferences: Codable, Equatable {
    var minAge: Int = 18
    var maxAge: Int = 60
    var hideCopycats: Bool = false   // kept for snapshot backward compat; unused

    // Premium (Pass-gated)
    var verifiedOnly: Bool = false
    var interests: Set<String> = []

    var activeCount: Int {
        var n = 0
        if minAge > 18 || maxAge < 60 { n += 1 }
        if verifiedOnly { n += 1 }
        if !interests.isEmpty { n += 1 }
        return n
    }

    func matches(_ p: Profile) -> Bool {
        guard p.age >= minAge, p.age <= maxAge else { return false }
        if verifiedOnly, !p.verified { return false }
        if !interests.isEmpty, interests.isDisjoint(with: Set(p.interests)) { return false }
        return true
    }

    static let interestPool = ["Art", "Travel", "Food", "Fitness", "Music", "Startups",
                               "Wine", "Film", "Reading", "Dogs", "Nightlife", "Design"]
}
