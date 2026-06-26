import Foundation

struct ChatMessage: Identifiable, Codable, Hashable {
    var id = UUID()
    var fromMe: Bool
    var text: String
    var date: Date = .now
    /// System lines (the invite, "date completed") render centered & muted.
    var isSystem: Bool = false
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

    /// The counterpart, from the perspective of the logged-in `role`.
    func other(for role: Role) -> Profile { role == .woman ? bid.man : bid.woman }
}
