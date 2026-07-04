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
    /// The other side has read your latest message (Black Card read receipts).
    var seenByOther: Bool = false
    /// Bumble-style urgency: set when the match is created, cleared the moment
    /// the current user sends their first reply. If it lapses with no reply,
    /// the match goes cold.
    var expiresAt: Date? = nil

    /// The counterpart, from the perspective of the logged-in `role`.
    func other(for role: Role) -> Profile { role == .woman ? bid.man : bid.woman }

    /// True once the reply window has lapsed with no reply from the current user.
    var isExpired: Bool {
        guard phase == .chatting, let expiresAt else { return false }
        return Date() > expiresAt
    }
}
