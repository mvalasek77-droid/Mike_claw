import Foundation

struct ChatMessage: Identifiable, Codable, Hashable {
    var id = UUID()
    var fromMe: Bool
    var text: String
    var date: Date = .now
    /// System lines (the invite, "date completed") render centered & muted.
    var isSystem: Bool = false
    /// A double-tapped emoji reaction, iMessage-style. Nil = no reaction.
    var reaction: String? = nil

    init(id: UUID = UUID(), fromMe: Bool, text: String, date: Date = .now,
         isSystem: Bool = false, reaction: String? = nil) {
        self.id = id
        self.fromMe = fromMe
        self.text = text
        self.date = date
        self.isSystem = isSystem
        self.reaction = reaction
    }

    // Backward-compatible decode — see Profile.init(from:).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fromMe = try c.decodeIfPresent(Bool.self, forKey: .fromMe) ?? false
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        isSystem = try c.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
        reaction = try c.decodeIfPresent(String.self, forKey: .reaction)
    }
}

/// What stage a match is in. The flow: accepted → chatting → date marked done →
/// both sides leave a review.
enum MatchPhase: String, Codable {
    case chatting
    case dateDone
    case closed
}

/// A connection created when a woman accepts a man's bid. The woman always sends
/// the first invite (per the brief — "man gets invite from woman").
struct Match: Identifiable, Codable, Hashable {
    var id = UUID()
    var bid: Bid
    var messages: [ChatMessage] = []
    var phase: MatchPhase = .chatting
    var manReviewedWoman: Bool = false   // man left his review of her
    var womanReviewedMan: Bool = false   // woman left her review of him
    var spentAmount: Int? = nil          // what he actually paid, set at review
    /// Each side attests independently that the date actually happened. When
    /// both flags are true the match is Gavel Confirmed — the credit engine
    /// treats it as gold: full trait weight for her, full deadbeat protection
    /// for him. If either side leaves this off the review still posts, but
    /// the credit signal is discounted (self-reported, not corroborated).
    var manConfirmedMet: Bool = false
    var womanConfirmedMet: Bool = false
    /// True only when both sides confirm the meetup happened.
    var gavelConfirmed: Bool { manConfirmedMet && womanConfirmedMet }
    /// The other side has read your latest message (Black Card read receipts).
    var seenByOther: Bool = false
    /// Bumble-style urgency: set when the match is created, cleared the moment
    /// the current user sends their first reply. If it lapses with no reply,
    /// the match goes cold.
    var expiresAt: Date? = nil
    /// The bidder paid the real-world "Reserve the date" booking fee (via
    /// Stripe, kept by the platform). Purely a real-world confirmation — it
    /// unlocks NO in-app content, by design (Apple compliance). Set from the
    /// consumables Worker's reservation status on foreground.
    var dateReserved: Bool = false

    /// The counterpart, from the perspective of the logged-in `role`.
    func other(for role: Role) -> Profile { role == .woman ? bid.man : bid.woman }

    /// True once the reply window has lapsed with no reply from the current user.
    var isExpired: Bool {
        guard phase == .chatting, let expiresAt else { return false }
        return Date() > expiresAt
    }

    init(id: UUID = UUID(), bid: Bid, messages: [ChatMessage] = [],
         phase: MatchPhase = .chatting, manReviewedWoman: Bool = false,
         womanReviewedMan: Bool = false, spentAmount: Int? = nil,
         manConfirmedMet: Bool = false, womanConfirmedMet: Bool = false,
         seenByOther: Bool = false, expiresAt: Date? = nil,
         dateReserved: Bool = false) {
        self.id = id
        self.bid = bid
        self.messages = messages
        self.phase = phase
        self.manReviewedWoman = manReviewedWoman
        self.womanReviewedMan = womanReviewedMan
        self.spentAmount = spentAmount
        self.manConfirmedMet = manConfirmedMet
        self.womanConfirmedMet = womanConfirmedMet
        self.seenByOther = seenByOther
        self.expiresAt = expiresAt
        self.dateReserved = dateReserved
    }

    // Backward-compatible decode — see Profile.init(from:).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bid = try c.decode(Bid.self, forKey: .bid)
        messages = try c.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        phase = try c.decodeIfPresent(MatchPhase.self, forKey: .phase) ?? .chatting
        manReviewedWoman = try c.decodeIfPresent(Bool.self, forKey: .manReviewedWoman) ?? false
        womanReviewedMan = try c.decodeIfPresent(Bool.self, forKey: .womanReviewedMan) ?? false
        spentAmount = try c.decodeIfPresent(Int.self, forKey: .spentAmount)
        manConfirmedMet = try c.decodeIfPresent(Bool.self, forKey: .manConfirmedMet) ?? false
        womanConfirmedMet = try c.decodeIfPresent(Bool.self, forKey: .womanConfirmedMet) ?? false
        seenByOther = try c.decodeIfPresent(Bool.self, forKey: .seenByOther) ?? false
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        dateReserved = try c.decodeIfPresent(Bool.self, forKey: .dateReserved) ?? false
    }
}
