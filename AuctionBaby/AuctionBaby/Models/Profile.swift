import SwiftUI

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
    /// Gavel Confirmed — both sides attested the date happened. Missing/false
    /// = self-reported only; the credit engine weights this review lighter.
    var gavelConfirmed: Bool = false

    init(id: UUID = UUID(), authorName: String, authorHue: Double, date: Date = .now,
         stars: Int, text: String, traits: [String: Int] = [:],
         interestCategories: [String] = [], paidBid: Bool? = nil,
         bidAmount: Int? = nil, spentAmount: Int? = nil, gavelConfirmed: Bool = false) {
        self.id = id
        self.authorName = authorName
        self.authorHue = authorHue
        self.date = date
        self.stars = stars
        self.text = text
        self.traits = traits
        self.interestCategories = interestCategories
        self.paidBid = paidBid
        self.bidAmount = bidAmount
        self.spentAmount = spentAmount
        self.gavelConfirmed = gavelConfirmed
    }

    // Backward-compatible decode: synthesized Codable throws on ANY missing
    // key for non-optional fields — so every field added after a user's
    // snapshot was written would wipe their whole account. decodeIfPresent +
    // defaults means old JSON always decodes. (Same pattern on every
    // persisted model below and in Bid/Match/FilterPreferences.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        authorHue = try c.decodeIfPresent(Double.self, forKey: .authorHue) ?? 0.5
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 3
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        traits = try c.decodeIfPresent([String: Int].self, forKey: .traits) ?? [:]
        interestCategories = try c.decodeIfPresent([String].self, forKey: .interestCategories) ?? []
        paidBid = try c.decodeIfPresent(Bool.self, forKey: .paidBid)
        bidAmount = try c.decodeIfPresent(Int.self, forKey: .bidAmount)
        spentAmount = try c.decodeIfPresent(Int.self, forKey: .spentAmount)
        gavelConfirmed = try c.decodeIfPresent(Bool.self, forKey: .gavelConfirmed) ?? false
    }
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
    /// The user-uploaded primary photo as JPEG data. Wins over `photoName` when
    /// present. Populated via `PhotoUploadStep` → `PhotosPicker` in onboarding
    /// and the profile editor. Persisted alongside the rest of the profile in
    /// the AES-GCM encrypted archive.
    var photoData: Data? = nil
    /// Additional photos in gallery order (0..n-1); `photoData` above is the
    /// primary shown on cards. Capped at 5 extras by the UI (6 total, matching
    /// Hinge). Kept as [Data] rather than paths because `EncryptedArchive`
    /// already serialises the whole `Profile` Codable.
    var photoGallery: [Data] = []
    var prompts: [Prompt] = []
    var interests: [String] = []
    /// Height + smoking/drinking/kids/education used by the bidder-side Reserve
    /// Requirements filters. Every field defaults to nil so pre-Lifestyle
    /// snapshots decode cleanly and existing profiles pass every filter.
    var lifestyle: Lifestyle = Lifestyle()
    /// Woman-authored first-message script the auto-generated "you're in"
    /// invite falls back to when set. Bumble's Opening Moves: she sets the
    /// question once, every accepted bidder gets the same opener. Optional
    /// so untouched profiles keep the current default openers.
    var openingBidScript: String? = nil
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
    var declinedBids: Int = 0             // bids women passed on — small credit drag
    /// Trillionaire is *earned*, not just bought: true only after he pays the
    /// full $9,999 on a date and the woman confirms it. Until then the badge
    /// reads "Pending".
    var trillionaireVerified: Bool = false

    // Explicit memberwise init — adding init(from:) below removes the
    // synthesized one, and SampleData + the stores construct Profiles
    // everywhere. Parameter order mirrors property order exactly.
    init(id: UUID = UUID(), name: String, age: Int, role: Role, location: String,
         bio: String, hue: Double, photoName: String? = nil, photoData: Data? = nil,
         photoGallery: [Data] = [], prompts: [Prompt] = [], interests: [String] = [],
         lifestyle: Lifestyle = Lifestyle(), openingBidScript: String? = nil,
         reviews: [DateReview] = [], verified: Bool = false, startingBid: Int? = nil,
         isCopycat: Bool = false, copycatStyle: CopycatStyle = .glam,
         masterpiece: Bool = false, archetype: Archetype = .none,
         copycatBids: Int = 0, declinedBids: Int = 0, trillionaireVerified: Bool = false) {
        self.id = id
        self.name = name
        self.age = age
        self.role = role
        self.location = location
        self.bio = bio
        self.hue = hue
        self.photoName = photoName
        self.photoData = photoData
        self.photoGallery = photoGallery
        self.prompts = prompts
        self.interests = interests
        self.lifestyle = lifestyle
        self.openingBidScript = openingBidScript
        self.reviews = reviews
        self.verified = verified
        self.startingBid = startingBid
        self.isCopycat = isCopycat
        self.copycatStyle = copycatStyle
        self.masterpiece = masterpiece
        self.archetype = archetype
        self.copycatBids = copycatBids
        self.declinedBids = declinedBids
        self.trillionaireVerified = trillionaireVerified
    }

    // Backward-compatible decode — see the note on DateReview.init(from:).
    // A Profile written by ANY previous build must keep decoding forever;
    // one thrown key here wipes the whole account snapshot (and with it the
    // appAccountToken that keys the server-side money surfaces).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        age = try c.decodeIfPresent(Int.self, forKey: .age) ?? 25
        role = try c.decodeIfPresent(Role.self, forKey: .role) ?? .woman
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
        hue = try c.decodeIfPresent(Double.self, forKey: .hue) ?? 0.5
        photoName = try c.decodeIfPresent(String.self, forKey: .photoName)
        photoData = try c.decodeIfPresent(Data.self, forKey: .photoData)
        photoGallery = try c.decodeIfPresent([Data].self, forKey: .photoGallery) ?? []
        prompts = try c.decodeIfPresent([Prompt].self, forKey: .prompts) ?? []
        interests = try c.decodeIfPresent([String].self, forKey: .interests) ?? []
        lifestyle = try c.decodeIfPresent(Lifestyle.self, forKey: .lifestyle) ?? Lifestyle()
        openingBidScript = try c.decodeIfPresent(String.self, forKey: .openingBidScript)
        reviews = try c.decodeIfPresent([DateReview].self, forKey: .reviews) ?? []
        verified = try c.decodeIfPresent(Bool.self, forKey: .verified) ?? false
        startingBid = try c.decodeIfPresent(Int.self, forKey: .startingBid)
        isCopycat = try c.decodeIfPresent(Bool.self, forKey: .isCopycat) ?? false
        copycatStyle = try c.decodeIfPresent(CopycatStyle.self, forKey: .copycatStyle) ?? .glam
        masterpiece = try c.decodeIfPresent(Bool.self, forKey: .masterpiece) ?? false
        archetype = try c.decodeIfPresent(Archetype.self, forKey: .archetype) ?? .none
        copycatBids = try c.decodeIfPresent(Int.self, forKey: .copycatBids) ?? 0
        declinedBids = try c.decodeIfPresent(Int.self, forKey: .declinedBids) ?? 0
        trillionaireVerified = try c.decodeIfPresent(Bool.self, forKey: .trillionaireVerified) ?? false
    }
}

// MARK: - Derived "credit scores"

/// The lot's honors ladder — auction-house artwork tiers a woman climbs with
/// real activity on the floor. Every rung below Masterpiece is achievable
/// through dates and reputation; **Masterpiece** alone requires a Trillionaire
/// paying $1,000,000 for one evening, and cannot be climbed to.
enum ArtTier: Int, Codable, CaseIterable, Comparable, Identifiable {
    case freshCanvas = 0   // new to the floor
    case sketch            // first reviewed date
    case limitedPrint      // a small following
    case galleryPiece      // established, verified
    case collectorsItem    // sought after
    case exhibitionStar    // the room turns
    case masterpiece       // the $1,000,000 evening

    var id: Int { rawValue }
    static func < (l: ArtTier, r: ArtTier) -> Bool { l.rawValue < r.rawValue }

    var title: String {
        switch self {
        case .freshCanvas: return "Fresh Canvas"
        case .sketch: return "Sketch"
        case .limitedPrint: return "Limited Print"
        case .galleryPiece: return "Gallery Piece"
        case .collectorsItem: return "Collector's Item"
        case .exhibitionStar: return "Exhibition Star"
        case .masterpiece: return "Masterpiece"
        }
    }

    var systemImage: String {
        switch self {
        case .freshCanvas: return "square.dashed"
        case .sketch: return "pencil.line"
        case .limitedPrint: return "doc.on.doc.fill"
        case .galleryPiece: return "photo.artframe"
        case .collectorsItem: return "seal.fill"
        case .exhibitionStar: return "sparkles.rectangle.stack.fill"
        case .masterpiece: return "rosette"
        }
    }

    var tint: Color {
        switch self {
        case .freshCanvas: return Theme.inkFaint
        case .sketch: return Theme.inkSoft
        case .limitedPrint: return Theme.verify
        case .galleryPiece: return Theme.success
        case .collectorsItem: return Theme.rose
        case .exhibitionStar: return Theme.gold
        case .masterpiece: return Theme.goldSoft
        }
    }

    /// What it takes — shown on the honors ladder.
    var requirement: String {
        switch self {
        case .freshCanvas: return "Step onto the floor"
        case .sketch: return "1 reviewed date"
        case .limitedPrint: return "3 reviewed dates · credit 550+"
        case .galleryPiece: return "6 reviewed dates · credit 680+ · verified"
        case .collectorsItem: return "9 reviewed dates · credit 780+"
        case .exhibitionStar: return "12 reviewed dates · credit 840+"
        case .masterpiece: return "A Trillionaire pays $1,000,000 for one evening"
        }
    }
}

/// One line of a credit report: what moved the number, by how much, and the
/// bureau's comment. Both sides' headline scores are computed *from* these, so
/// the printed report always adds up.
struct CreditFactor: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let icon: String
    let points: Int
    let comment: String
}

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

    /// Her "Showcase Credit" report: base 300, perfect 900 — the same bureau
    /// scale as the men, but built on who she *is* on a date. Personality
    /// carries the weight: Fun counts double, then the other four traits,
    /// then consistency (review depth), star average, identity, and the
    /// Masterpiece seal.
    var showcaseFactors: [CreditFactor] {
        var f: [CreditFactor] = []
        let t = traitAverages
        let fun = t[.fun] ?? 0

        // 1. Personality — up to +300. Weighted: (2·Fun + the rest) / 6.
        let interesting = t[.interesting] ?? 0
        let social = t[.social] ?? 0
        let polite = t[.polite] ?? 0
        let genuine = t[.genuine] ?? 0
        let weighted: Double = Double(2 * fun + interesting + social + polite + genuine) / 6.0   // 0–5
        let personality = t.isEmpty ? 180 : Int((weighted / 5.0 * 300).rounded())
        f.append(CreditFactor(
            name: "Personality", icon: "party.popper.fill", points: personality,
            comment: t.isEmpty ? "Unrated — the floor prices her on presence alone, for now."
                : fun >= 4.5 ? "The date everyone talks about after. Fun carries this report."
                : weighted >= 4.0 ? "Warm, sharp, easy company — dates say the evening flew."
                : weighted >= 3.0 ? "Good company; a little more spark would move this number."
                : "Dates report a flat evening. Personality is the whole game here."))

        // 2. Star average — up to +100.
        let stars = Int((overallStars / 5.0 * 100).rounded())
        f.append(CreditFactor(
            name: "Date ratings", icon: "star.fill", points: stars,
            comment: reviews.isEmpty ? "No rated dates yet."
                : overallStars >= 4.5 ? String(format: "%.1f★ average — men leave better than they arrived.", overallStars)
                : String(format: "%.1f★ average across %d date%@.", overallStars, reviews.count,
                         reviews.count == 1 ? "" : "s")))

        // 3. Consistency — up to +120 for a deep, recent review history.
        let depth = min(reviews.count, 12) * 10
        f.append(CreditFactor(
            name: "Consistency", icon: "calendar", points: depth,
            comment: reviews.isEmpty ? "The book on her is still open."
                : reviews.count >= 8 ? "\(reviews.count) reviewed dates — the number is earned, not guessed."
                : "\(reviews.count) reviewed date\(reviews.count == 1 ? "" : "s") on record."))

        // 4. Identity — +30.
        f.append(CreditFactor(
            name: "Identity", icon: "checkmark.seal.fill", points: verified ? 30 : 0,
            comment: verified ? "Selfie-verified — bidders bid harder on a real face."
                             : "Unverified — the blue check raises every bid."))

        // 5. Gavel Confirmed dates — corroborated meetups carry more weight
        // than self-reported ones. +10 per, capped at +60. This is what makes
        // the credit engine resistant to solo review-farming.
        let confirmed = reviews.filter(\.gavelConfirmed).count
        if confirmed > 0 {
            f.append(CreditFactor(
                name: "Gavel Confirmed", icon: "checkmark.seal.fill",
                points: min(confirmed * 10, 60),
                comment: confirmed == 1
                    ? "1 date confirmed by both sides — corroborated, not self-reported."
                    : "\(confirmed) dates confirmed by both sides — the record is on the books."))
        }

        // 6. Masterpiece — +50. The rarest line on any report.
        if masterpiece {
            f.append(CreditFactor(
                name: "Masterpiece", icon: "rosette", points: 50,
                comment: "A Trillionaire paid $1,000,000 in full for one evening. Certified."))
        }
        return f
    }

    /// Her headline Showcase Credit: 300 base + the factor sum, clamped 300–900.
    var showcaseCredit: Int {
        let sum = showcaseFactors.reduce(0) { $0 + $1.points }
        return min(900, max(300, 300 + sum))
    }

    var showcaseTier: String { Self.tierName(showcaseCredit) }

    /// Where she sits on the honors ladder. Every rung below Masterpiece is
    /// earned with dates + credit; Masterpiece is minted, never climbed to.
    var artTier: ArtTier {
        if masterpiece { return .masterpiece }
        let n = reviews.count, c = showcaseCredit
        if n >= 12 && c >= 840 { return .exhibitionStar }
        if n >= 9 && c >= 780 { return .collectorsItem }
        if n >= 6 && c >= 680 && verified { return .galleryPiece }
        if n >= 3 && c >= 550 { return .limitedPrint }
        if n >= 1 { return .sketch }
        return .freshCanvas
    }

    /// The next rung, for the ladder card. `nil` at Exhibition Star — the only
    /// thing above it can't be climbed to.
    var nextArtTier: ArtTier? {
        guard artTier < .exhibitionStar else { return nil }
        return ArtTier(rawValue: artTier.rawValue + 1)
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

    /// His "Auction Credit" report: base 300, perfect 900. Computed *from* the
    /// factor list so the printed report always sums to the headline number,
    /// like a real bureau statement. The only path to 900: verified
    /// Trillionaire, flawless payment history, a deep track record, identity
    /// verified — and never once baited by a Copycat.
    var creditFactors: [CreditFactor] {
        var f: [CreditFactor] = []

        // 1. Payment history — the biggest slice, like FICO. Up to +240.
        let pay = Int((Double(deadbeatScore) * 2.4).rounded())
        f.append(CreditFactor(
            name: "Payment history", icon: "creditcard.fill", points: pay,
            comment: reviews.compactMap(\.paidBid).isEmpty
                ? "No dates on record yet — the floor extends the benefit of the doubt."
                : deadbeatScore >= 95 ? "Pays what he bids, every time. The floor trusts this man."
                : deadbeatScore >= 70 ? "Mostly good for it — one short check follows you around here."
                : deadbeatScore >= 40 ? "Talks bigger than he pays. Women check the reviews first."
                : "A pattern of unpaid bids. On this floor, that's the whole story."))

        // 2. Status — the archetype tier, up to +220 (+20 more once verified).
        let tierPts = [0, 20, 30, 40, 80, 120, 150, 185, 220][archetype.rawValue]
        let statusPts = tierPts + (archetype == .trillionaire && trillionaireVerified ? 20 : 0)
        f.append(CreditFactor(
            name: "Status", icon: archetype.systemImage, points: statusPts,
            comment: archetype == .none ? "Unbadged. The floor has only his word."
                : archetype == .trillionaire && trillionaireVerified
                    ? "Verified Trillionaire — bid the full $9,999, paid it, confirmed."
                : archetype == .trillionaire ? "Trillionaire pending — bought the badge, hasn't proven it on a date."
                : "\(archetype.title) — paid for, worn openly."))

        // 3. Track record — up to +90 for repeat, completed dates.
        let track = min(datesCompleted, 15) * 6
        f.append(CreditFactor(
            name: "Track record", icon: "calendar", points: track,
            comment: datesCompleted == 0 ? "No completed dates yet."
                : datesCompleted >= 10 ? "\(datesCompleted) dates completed — a regular, and it shows."
                : "\(datesCompleted) date\(datesCompleted == 1 ? "" : "s") completed and reviewed."))

        // 4. Identity — +30 for the blue check.
        f.append(CreditFactor(
            name: "Identity", icon: "checkmark.seal.fill", points: verified ? 30 : 0,
            comment: verified ? "Selfie-verified. A real face behind the bids."
                             : "Unverified — a blue check would lift every number here."))

        // 5. Gavel Confirmed — +12 per corroborated meetup (capped at +72).
        // Higher weight than the woman's side because payment history is the
        // biggest slice already; here it's the anti-fraud accelerator.
        let confirmed = reviews.filter(\.gavelConfirmed).count
        if confirmed > 0 {
            f.append(CreditFactor(
                name: "Gavel Confirmed", icon: "checkmark.seal.fill",
                points: min(confirmed * 12, 72),
                comment: confirmed == 1
                    ? "1 date confirmed by both sides — the record isn't self-reported."
                    : "\(confirmed) dates confirmed by both sides — the floor trusts corroborated history."))
        }

        // 6. Copycat incidents — −40 each. The floor never forgets.
        if copycatBids > 0 {
            f.append(CreditFactor(
                name: "Copycat incidents", icon: "sparkles", points: -copycatBids * 40,
                comment: copycatBids == 1 ? "Baited once by an AI Copycat. Everyone saw."
                                          : "Baited \(copycatBids) times by AI Copycats. Study the floor."))
        }

        // 6. Passed bids — a light drag; rejection is data too.
        if declinedBids > 0 {
            f.append(CreditFactor(
                name: "Passed bids", icon: "hand.thumbsdown", points: -min(declinedBids * 8, 60),
                comment: "\(declinedBids) bid\(declinedBids == 1 ? "" : "s") declined — aim better or bid stronger."))
        }
        return f
    }

    /// His headline Auction Credit: 300 base + the factor sum, clamped 300–900.
    var auctionCredit: Int {
        let sum = creditFactors.reduce(0) { $0 + $1.points }
        return min(900, max(300, 300 + sum))
    }

    var creditTier: String { Self.tierName(auctionCredit) }

    static func tierName(_ score: Int) -> String {
        switch score {
        case 900...: return "Perfect"
        case 820..<900: return "Exceptional"
        case 740..<820: return "Very Good"
        case 660..<740: return "Good"
        case 560..<660: return "Fair"
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

    /// A one-line read on where he stands, used to keep his written reviews and
    /// his credit number telling the same story.
    var creditStanding: String { Self.tierName(auctionCredit) }

    /// "On the Floor Now" — a deterministic hour-of-day rotation that flips
    /// a subset of profiles to "live" so the feed carries the same live-
    /// presence energy Bumble/Tinder use as their #1 DAU lever. About 30% of
    /// ALL profiles read as active in any given hour — copycats included,
    /// on the same odds. They must be: if the bait never lit up, a patient
    /// user could identify every Copycat by absence-of-presence, and the
    /// house rule is that they're indistinguishable until after the bid.
    /// Deterministic on (id, hour) so the signal doesn't flicker mid-scroll.
    var isOnTheFloorNow: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let idBytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        let seed = Int(idBytes[0]) &+ Int(idBytes[1]) &* 7 &+ hour &* 13
        return seed % 10 < 3   // ~30% active
    }

    /// True when at least one lifestyle field is set; the detail card uses
    /// this to hide the whole section on profiles that never answered.
    var hasAnyLifestyle: Bool {
        lifestyle.heightCm != nil || lifestyle.smoking != nil
            || lifestyle.drinking != nil || lifestyle.kids != nil
            || lifestyle.education != nil
    }

    /// Returns a copy with a deterministic Lifestyle seeded from the profile's
    /// UUID, so seeded sample data has enough lifestyle answers for Reserve
    /// Requirements to actually bite. Real users' Lifestyle stays untouched
    /// (we only seed when `lifestyle` is the default all-nil struct AND the
    /// profile is not the current user).
    func seededLifestyle() -> Profile {
        guard lifestyle == Lifestyle() else { return self }
        var copy = self
        // Draw four independent bits from the UUID's low bytes so different
        // fields don't correlate. Deterministic because UUID is fixed.
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        func pick<T>(_ options: [T], byte: Int) -> T {
            options[Int(bytes[byte % bytes.count]) % options.count]
        }
        // Only ~60% of profiles get each attribute — real people leave
        // things blank, and the "unset always passes" rule makes that fine.
        if bytes[0] % 5 < 3 {
            copy.lifestyle.heightCm = 160 + Int(bytes[1]) % 30   // 160–189 cm
        }
        if bytes[2] % 5 < 3 {
            copy.lifestyle.smoking = pick(Lifestyle.Smoking.allCases, byte: 3)
        }
        if bytes[4] % 5 < 3 {
            copy.lifestyle.drinking = pick(Lifestyle.Drinking.allCases, byte: 5)
        }
        if bytes[6] % 5 < 3 {
            copy.lifestyle.kids = pick(Lifestyle.Kids.allCases, byte: 7)
        }
        if bytes[8] % 5 < 3 {
            copy.lifestyle.education = pick(Lifestyle.Education.allCases, byte: 9)
        }
        return copy
    }

    /// Suggested opening lines, generated from this profile's own prompts and
    /// interests — tapped to fill (not auto-send) the composer on a cold match,
    /// so nobody has to open with a bare "hey".
    var icebreakers: [String] {
        var lines: [String] = []
        if let p = prompts.first {
            lines.append("Okay, \"\(p.answer)\" — I need the full story on that.")
        }
        if prompts.count > 1 {
            lines.append("Your answer to \"\(prompts[1].question)\" got me. Tell me more?")
        }
        if let interest = interests.first {
            lines.append("Saw you're into \(interest.lowercased()) — good, me too. Where do you go?")
        }
        if lines.isEmpty { lines.append("So — where are we actually going?") }
        return Array(lines.prefix(3))
    }
}

// MARK: - Review copy

/// Generates woman→man review lines that always agree with his credit, so the
/// written word on a bidder can never contradict his number: a short check is
/// called out no matter what, and among men who *did* pay, the praise scales
/// with standing — poor credit reads guarded, exceptional credit reads glowing.
/// This is what keeps "bad credit → negative comments, and vice versa" true
/// everywhere a review is minted.
enum ReviewCopy {

    /// The verdict a woman leaves on him after the date.
    /// - Parameters:
    ///   - paid: did he honor *this* bid in full?
    ///   - credit: his Auction Credit coming into the date (his reputation).
    static func manVerdict(paid: Bool, credit: Int,
                           bidAmount: Int, spentAmount: Int) -> (stars: Int, text: String) {
        guard paid else {
            let lines = [
                "Bid \(Money.compact(bidAmount)), paid \(Money.compact(spentAmount)). Deadbeat.",
                "Talked a big number, came up short when the check landed. I covered the rest.",
                "His bid was theater. The bill was mine.",
                "Promised \(Money.compact(bidAmount)) and folded at the table. Ladies, read the reviews.",
            ]
            return (Int.random(in: 1...2), lines.randomElement()!)
        }
        switch credit {
        case 820...:
            let lines = [
                "Bid \(Money.compact(bidAmount)) and paid it without being asked twice. A gentleman.",
                "Exactly what his profile promised — paid in full, walked me out, texted the next day.",
                "The number's real. Paid every cent and made the whole night easy.",
            ]
            return (5, lines.randomElement()!)
        case 660..<820:
            let lines = [
                "Paid what he bid, no drama. Would say yes again.",
                "Good for it — kept his word and kept me laughing.",
                "Solid evening. Paid in full, no games.",
            ]
            return (Int.random(in: 4...5), lines.randomElement()!)
        case 560..<660:
            let lines = [
                "Paid this time — the reviews had me nervous, but he came through.",
                "Honored the bid. Still earning trust back, but it's a start.",
                "Came correct tonight. Better than his record led me to expect.",
            ]
            return (Int.random(in: 3...4), lines.randomElement()!)
        default:
            let lines = [
                "Paid, to his credit — though I checked the reviews twice before saying yes.",
                "Honored it this once. The floor's still watching him, and so am I.",
                "Surprised me by paying. His history said otherwise.",
            ]
            return (Int.random(in: 3...3), lines.randomElement()!)
        }
    }
}
