import Foundation

enum BidStatus: String, Codable {
    case pending
    case accepted
    case declined
}

/// A single bid: a man (`man`) offering an `amount` he'll spend on a date with
/// a woman (`woman`). Snapshots both profiles so the record is self-contained
/// and survives independently of the live floor.
struct Bid: Identifiable, Codable, Hashable {
    var id = UUID()
    var man: Profile
    var woman: Profile
    var amount: Int
    var note: String = ""
    var status: BidStatus = .pending
    var createdAt: Date = .now

    /// Bidding on an AI copycat is always disclosed and counts against the man.
    var onCopycat: Bool { woman.isCopycat }

    /// Only a Trillionaire paying the full $9,999 (the Trillionaire tier price)
    /// on a date can mint a Masterpiece — and only once the woman confirms it.
    /// This flag is the *eligibility*; the confirmation gate is applied at review.
    var qualifiesForMasterpiece: Bool {
        man.archetype == .trillionaire && amount >= Archetype.trillionaire.price
    }
}

/// Where a bid sits against the (simulated) competing field on the same lot.
/// Surfaced only to Pass subscribers — free bidders bid blind.
enum BidRank: Equatable {
    case top
    case outbid(position: Int, leader: Int)
}

extension Bid {
    /// Deterministic, stable rank used for the "are you the top bid?" reveal.
    /// Copycats always read as top (that's the bait); otherwise the bid is
    /// compared to a simulated competitive ceiling derived from her worth.
    var simulatedRank: BidRank {
        if onCopycat { return .top }
        let competitorTop = max(woman.startingBid ?? 0, Int(Double(woman.marketValue) * 1.15))
        if amount >= competitorTop { return .top }
        let position = 2 + abs(amount &* 31 &+ woman.name.count) % 4
        return .outbid(position: position, leader: competitorTop)
    }
}
