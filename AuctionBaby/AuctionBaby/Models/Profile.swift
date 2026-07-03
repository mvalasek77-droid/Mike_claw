import Foundation

/// A Hinge-style prompt + answer shown on a profile.
struct Prompt: Identifiable, Codable, Hashable {
    var id = UUID()
    var question: String
    var answer: String
}

/// The five traits a man rates a woman on after a date. These roll up into her
/// public "Showcase" score — her on-the-floor credit rating.
enum Trait: String, Codable, CaseIterable, Identifiable {
    case fun = "Fun"
    case interesting = "Interesting"
    case social = "Social"
    case polite = "Polite"
    case genuine = "Genuine"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .fun: return "party.popper.fill"
        case .interesting: return "brain.head.profile"
        case .social: return "bubble.left.and.bubble.right.fill"
        case .polite: return "hands.sparkles.fill"
        case .genuine: return "heart.fill"
        }
    }
}

/// One date review. Direction is implied by which array it lives in:
/// - on a **woman** → a man's review of her (carries `traits`)
/// - on a **man** → a woman's review of him (carries `paidBid` / `spentAmount`)
struct DateReview: Identifiable, Codable, Hashable {
    var id = UUID()
    var authorName: String
    var authorHue: Double
    var date: Date = .now
    var stars: Int                       // 1–5 overall
    var text: String

    // man → woman
    var traits: [String: Int] = [:]      // Trait.rawValue : 1–5
    var interestCategories: [String] = [] // "categories woman would be interested in"

    // woman → man
    var paidBid: Bool? = nil             // did he actually spend the bid?
    var bidAmount: Int? = nil
    var spentAmount: Int? = nil
}

/// The "look" a copycat lure is styled around. Drives the synthetic portrait's
/// palette and the swimwear/athleisure cue — conveyed through colour and a
/// stylised silhouette, never photographic bodies, so the lure stays tasteful,
/// obviously AI-generated, and App-Store-safe.
enum CopycatStyle: String, Codable, CaseIterable, Hashable {
    case poolside   // bikini · turquoise pool light
    case beach      // bikini · warm sunset sand
    case yoga       // yoga pants · lavender studio
    case glam       // couture · magenta + gold

    var caption: String {
        switch self {
        case .poolside: return "Bikini · Poolside"
        case .beach: return "Bikini · Beach"
        case .yoga: return "Yoga · Studio"
        case .glam: return "Couture · Glam"
        }
    }

    /// Gradient hue stops (0–1) for the iridescent backdrop.
    var hues: [Double] {
        switch self {
        case .poolside: return [0.50, 0.46, 0.13]
        case .beach: return [0.06, 0.02, 0.11]
        case .yoga: return [0.74, 0.80, 0.92]
        case .glam: return [0.90, 0.84, 0.95]
        }
    }

    var accent: Color {
        switch self {
        case .poolside: return Color(hue: 0.50, saturation: 0.75, brightness: 0.95)
        case .beach: return Color(hue: 0.06, saturation: 0.80, brightness: 0.98)
        case .yoga: return Color(hue: 0.78, saturation: 0.55, brightness: 0.96)
        case .glam: return Color(hue: 0.90, saturation: 0.70, brightness: 0.98)
        }
    }
}

/// A person on the floor. One struct for both sides; role-specific fields are
/// simply unused on the other side. Snapshots of these travel inside bids and
/// matches, so the type is a value type end-to-end.
struct Profile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var age: Int
    var role: Role
    var location: String
    var bio: String
    var hue: Double                       // avatar gradient seed, 0–1
    /// Asset-catalog image name for a real profile photo. When present (and the
    /// asset exists), it renders everywhere instead of the generated portrait —
    /// drop licensed photos into Resources/Assets.xcassets and reference them
    /// here. Optional + defaulted, so old snapshots decode unchanged.
    var photoName: String? = nil
    var prompts: [Prompt] = []
    var interests: [String] = []
    var reviews: [DateReview] = []
    /// Identity-verified (selfie match). Copycats can never be verified — it's
    /// the strongest "this is a real human" signal in the app.
    var verified: Bool = false

    // MARK: Woman-specific
    var startingBid: Int? = nil           // optional floor
    var isCopycat: Bool = false           // AI-generated lure
    var copycatStyle: CopycatStyle = .glam // how the lure portrait is styled
    var masterpiece: Bool = false         // minted by a Trillionaire's $1M date

    // MARK: Man-specific
    var archetype: Archetype = .none
    var copycatBids: Int = 0              // bids placed on copycats — reputation hit
    /// Trillionaire is *earned*, not just bought: true only after he pays the
    /// full $9,999 on a date and the woman confirms it. Until then the badge
    /// reads "Pending".
    var trillionaireVerified: Bool = false
}

// MARK: - Derived "credit scores"

extension Profile {

    /// He bought Trillionaire but hasn't completed the confirmed $9,999 date yet.
    var showsPendingTrillionaire: Bool { archetype == .trillionaire && !trillionaireVerified }

    // ----- Woman side -----

    /// Average of all trait scores a woman has received, 0–5.
    var traitAverages: [Trait: Double] {
        var sums: [Trait: (total: Int, count: Int)] = [:]
        for review in reviews {
            for trait in Trait.allCases {
                if let v = review.traits[trait.rawValue] {
                    let cur = sums[trait] ?? (0, 0)
                    sums[trait] = (cur.total + v, cur.count + 1)
                }
            }
        }
        return sums.mapValues { $0.count == 0 ? 0 : Double($0.total) / Double($0.count) }
    }

    var overallStars: Double {
        guard !reviews.isEmpty else { return 0 }
        return Double(reviews.map(\.stars).reduce(0, +)) / Double(reviews.count)
    }

    /// Her public "Showcase Score" (0–100) — the woman-side credit rating built
    /// from trait ratings, with a small bump for a Masterpiece.
    var showcaseScore: Int {
        let traits = traitAverages
        guard !traits.isEmpty else { return masterpiece ? 100 : 72 } // unrated baseline
        let avg = traits.values.reduce(0, +) / Double(traits.count) // 0–5
        var score = (avg / 5.0) * 100
        if masterpiece { score = min(100, score + 6) }
        return Int(score.rounded())
    }

    /// "Find out what you're worth": her market value is the headline number a
    /// bidder would expect to clear — driven by reputation and any floor she set.
    var marketValue: Int {
        var base = startingBid ?? 50
        base = Int(Double(base) * (0.8 + Double(showcaseScore) / 100.0))
        if masterpiece { base = Swift.max(base, 1_000_000) }
        return Swift.max(base, 25)
    }

    // ----- Man side -----

    /// Share of completed dates he actually paid in full, 0–100. Missing data
    /// is treated charitably (no reviews → 100, "benefit of the doubt").
    var deadbeatScore: Int {
        let judged = reviews.compactMap(\.paidBid)
        guard !judged.isEmpty else { return 100 }
        let paid = judged.filter { $0 }.count
        return Int((Double(paid) / Double(judged.count) * 100).rounded())
    }

    var datesCompleted: Int { reviews.count }

    /// His headline "Auction Credit" — a 300–850 credit-score analogue. Money
    /// (archetype tier) establishes the baseline; reliability (paying bids) and
    /// repeat business raise it; bidding on AI copycats drags it down.
    var auctionCredit: Int {
        // Archetype tier sets the floor of creditworthiness.
        let tierBoost = [300, 360, 400, 440, 540, 640, 720, 780, 820]
        var score = Double(tierBoost[archetype.rawValue])

        // Reliability swing: ±90 around the deadbeat score's midpoint.
        score += (Double(deadbeatScore) - 50) / 50 * 90

        // Repeat business builds trust (capped).
        score += Double(min(datesCompleted, 12)) * 4

        // Copycat bids are a public reputation hit.
        score -= Double(copycatBids) * 22

        return Int(min(850, max(300, score)).rounded())
    }

    var creditTier: String {
        switch auctionCredit {
        case 800...: return "Exceptional"
        case 740..<800: return "Very Good"
        case 670..<740: return "Good"
        case 580..<670: return "Fair"
        default: return "Poor"
        }
    }

    /// Categories a man's reviewers flagged as her likely interests — the
    /// "make categories a woman would be interested in" feature, aggregated.
    var endorsedCategories: [String] {
        var seen: [String] = []
        for review in reviews {
            for c in review.interestCategories where !seen.contains(c) { seen.append(c) }
        }
        return seen
    }
}
