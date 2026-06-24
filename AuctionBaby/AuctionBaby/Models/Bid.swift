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

    /// A trillionaire paying the full $1,000,000 is the only thing that can mint
    /// a Masterpiece for the woman he dates.
    var qualifiesForMasterpiece: Bool {
        man.archetype == .trillionaire && amount >= 1_000_000
    }
}
