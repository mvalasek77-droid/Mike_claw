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
    /// A "Gilded" bid — the premium attention move (the Rose of Auction Baby).
    /// Costs Gavels, pins to the top of her inbox with a gold ribbon, and
    /// nudges her toward accepting.
    var gilded: Bool = false
    /// Bid Insurance — a small Gavel premium paid up-front. If she declines
    /// or the match expires without acceptance, the premium is refunded and
    /// a consolation Gilded Bid credit lands in the wallet. Doesn't refund
    /// on a bid he cancels himself; that would be free-money farming.
    var insured: Bool = false

    /// A Whisper Bid — anonymous, no-Gavel, no-credit-impact signal of interest.
    /// She sees "someone whispered" without his name or archetype; he can
    /// escalate to a real bid once she nods back. Doesn't count against the
    /// free bid limit.
    var isWhisper: Bool = false
    /// How many auto-rebids led to this bid (0 = placed by the user). Caps the
    /// Reserve-perk auto-rebid chain so a decline streak can't loop forever.
    var rebidDepth: Int = 0
    /// If he bid in response to a specific prompt, the question he's replying to
    /// (Hinge-style targeted interaction). Optional → backward-compatible decode.
    var promptRef: String? = nil

    /// Bidding on an AI copycat is always disclosed and counts against the man.
    var onCopycat: Bool { woman.isCopycat }

    // Explicit memberwise init (init(from:) below suppresses the synthesized
    // one). Parameter order mirrors property order.
    init(id: UUID = UUID(), man: Profile, woman: Profile, amount: Int,
         note: String = "", status: BidStatus = .pending, createdAt: Date = .now,
         gilded: Bool = false, insured: Bool = false, isWhisper: Bool = false,
         rebidDepth: Int = 0, promptRef: String? = nil) {
        self.id = id
        self.man = man
        self.woman = woman
        self.amount = amount
        self.note = note
        self.status = status
        self.createdAt = createdAt
        self.gilded = gilded
        self.insured = insured
        self.isWhisper = isWhisper
        self.rebidDepth = rebidDepth
        self.promptRef = promptRef
    }

    // Backward-compatible decode — a Bid written by any previous build must
    // keep decoding; a thrown key here wipes the whole account snapshot.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        man = try c.decode(Profile.self, forKey: .man)
        woman = try c.decode(Profile.self, forKey: .woman)
        amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        status = try c.decodeIfPresent(BidStatus.self, forKey: .status) ?? .pending
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        gilded = try c.decodeIfPresent(Bool.self, forKey: .gilded) ?? false
        insured = try c.decodeIfPresent(Bool.self, forKey: .insured) ?? false
        isWhisper = try c.decodeIfPresent(Bool.self, forKey: .isWhisper) ?? false
        rebidDepth = try c.decodeIfPresent(Int.self, forKey: .rebidDepth) ?? 0
        promptRef = try c.decodeIfPresent(String.self, forKey: .promptRef)
    }

    /// The Masterpiece bar, per the house rules: a **Trillionaire** (the $9,999
    /// badge) who bids **$1,000,000** on the date — real-world money, settled in
    /// person, confirmed by her afterward. This flag is the *eligibility*; the
    /// confirmation gate is applied at review. Vanishingly rare, by design.
    static let masterpieceBid = 1_000_000
    var qualifiesForMasterpiece: Bool {
        man.archetype == .trillionaire && amount >= Bid.masterpieceBid
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
