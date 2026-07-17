import Foundation

/// The bidder's floor filters. Age range is free; the advanced filters
/// (verified-only, interest matching) and the Reserve Requirements
/// (dealbreakers) are a Pass perk.
struct FilterPreferences: Codable, Equatable {
    var minAge: Int = 18
    var maxAge: Int = 60
    var hideCopycats: Bool = false   // kept for snapshot backward compat; unused

    // Premium (Pass-gated)
    var verifiedOnly: Bool = false
    var interests: Set<String> = []

    // MARK: Reserve Requirements (dealbreakers, Reserve tier)
    /// Minimum height in cm; 0 = no requirement. Metric internally, rendered
    /// as ft/in in the UI to match how Americans set the number in Hinge.
    var minHeightCm: Int = 0
    /// Nil = "any". `.disqualify` means a woman/man with the OPPOSITE lifestyle
    /// is filtered out. The floor keeps everyone who is a match OR whose
    /// lifestyle is unset — we don't punish incomplete profiles.
    var smokingRequirement: Lifestyle.Smoking? = nil
    var drinkingRequirement: Lifestyle.Drinking? = nil
    var kidsRequirement: Lifestyle.Kids? = nil
    var educationRequirement: Lifestyle.Education? = nil

    init() {}

    // Backward-compatible decode — see Profile.init(from:). Filter fields
    // have been added in three separate releases; a thrown key here wipes
    // the whole account snapshot.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minAge = try c.decodeIfPresent(Int.self, forKey: .minAge) ?? 18
        maxAge = try c.decodeIfPresent(Int.self, forKey: .maxAge) ?? 60
        hideCopycats = try c.decodeIfPresent(Bool.self, forKey: .hideCopycats) ?? false
        verifiedOnly = try c.decodeIfPresent(Bool.self, forKey: .verifiedOnly) ?? false
        interests = try c.decodeIfPresent(Set<String>.self, forKey: .interests) ?? []
        minHeightCm = try c.decodeIfPresent(Int.self, forKey: .minHeightCm) ?? 0
        smokingRequirement = try c.decodeIfPresent(Lifestyle.Smoking.self, forKey: .smokingRequirement)
        drinkingRequirement = try c.decodeIfPresent(Lifestyle.Drinking.self, forKey: .drinkingRequirement)
        kidsRequirement = try c.decodeIfPresent(Lifestyle.Kids.self, forKey: .kidsRequirement)
        educationRequirement = try c.decodeIfPresent(Lifestyle.Education.self, forKey: .educationRequirement)
    }

    var activeCount: Int {
        var n = 0
        if minAge > 18 || maxAge < 60 { n += 1 }
        if verifiedOnly { n += 1 }
        if !interests.isEmpty { n += 1 }
        n += reserveRequirementCount
        return n
    }

    var reserveRequirementCount: Int {
        var n = 0
        if minHeightCm > 0 { n += 1 }
        if smokingRequirement != nil { n += 1 }
        if drinkingRequirement != nil { n += 1 }
        if kidsRequirement != nil { n += 1 }
        if educationRequirement != nil { n += 1 }
        return n
    }

    func matches(_ p: Profile) -> Bool {
        guard p.age >= minAge, p.age <= maxAge else { return false }
        if verifiedOnly, !p.verified { return false }
        if !interests.isEmpty, interests.isDisjoint(with: Set(p.interests)) { return false }

        // Reserve Requirements. Unset lifestyle fields on the target profile
        // pass every filter (we don't hide people who never answered), but a
        // stated mismatch fails.
        if minHeightCm > 0, let h = p.lifestyle.heightCm, h < minHeightCm { return false }
        if let req = smokingRequirement, let val = p.lifestyle.smoking, val != req { return false }
        if let req = drinkingRequirement, let val = p.lifestyle.drinking, val != req { return false }
        if let req = kidsRequirement, let val = p.lifestyle.kids, val != req { return false }
        if let req = educationRequirement, let val = p.lifestyle.education, val != req { return false }
        return true
    }

    static let interestPool = ["Art", "Travel", "Food", "Fitness", "Music", "Startups",
                               "Wine", "Film", "Reading", "Dogs", "Nightlife", "Design"]
}

/// Lifestyle attributes on a profile — kept together so a woman can complete
/// them once and every Reserve filter reads from the same struct. Every field
/// is optional so a fresh profile carries "unset" for all of them (which
/// passes every Reserve filter — see FilterPreferences.matches).
struct Lifestyle: Codable, Hashable {
    var heightCm: Int? = nil
    var smoking: Smoking? = nil
    var drinking: Drinking? = nil
    var kids: Kids? = nil
    var education: Education? = nil

    enum Smoking: String, Codable, CaseIterable, Identifiable {
        case never = "Never"
        case sometimes = "Sometimes"
        case regularly = "Regularly"
        var id: String { rawValue }
    }
    enum Drinking: String, Codable, CaseIterable, Identifiable {
        case never = "Never"
        case sometimes = "Socially"
        case regularly = "Regularly"
        var id: String { rawValue }
    }
    enum Kids: String, Codable, CaseIterable, Identifiable {
        case has = "Has kids"
        case wants = "Wants kids"
        case wantsSomeday = "Open to kids"
        case doesntWant = "No kids"
        var id: String { rawValue }
    }
    enum Education: String, Codable, CaseIterable, Identifiable {
        case highSchool = "High school"
        case undergrad = "Undergrad"
        case grad = "Grad school"
        case other = "Other"
        var id: String { rawValue }
    }
}
