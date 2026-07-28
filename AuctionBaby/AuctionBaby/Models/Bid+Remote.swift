import Foundation

// MARK: - RemoteBid → Bid adapter (slice 4b1b)

extension Bid {
    /// Convert a server-side `RemoteBid` — the shape the matching Worker
    /// returns from `/bids/incoming` and `/bids/outgoing` — into the local
    /// `Bid` shape the UI reads. Preserves `RemoteBid.id` as `Bid.id` so a
    /// tap on a row can send an accept/decline back to the same server row.
    ///
    /// The bid stores full `Profile` snapshots on both sides (self-contained
    /// records that survive the sim floor). For a signed-in user, we own our
    /// own profile locally; the OTHER side is materialized from the embedded
    /// `RemotePeer` snapshot the Worker shipped with the row (LEFT JOIN with
    /// `profiles` + `users`). Missing name → "Someone"; missing hue → 0.6.
    ///
    /// `direction` tells us who's "man" and who's "woman":
    ///   • `.inbox` (I'm the lot) → man = peer, woman = mine
    ///   • `.outbox` (I'm the bidder) → man = mine, woman = peer
    init(from remote: RemoteBid, mine: Profile, direction: RemoteBidDirection) {
        let peer = Profile(fromRemotePeer: remote.peer,
                           fallbackId: direction == .inbox ? remote.bidderId : remote.lotId,
                           role: direction == .inbox ? .man : .woman)
        let man = direction == .inbox ? peer : mine
        let woman = direction == .inbox ? mine : peer

        self.init(
            id: UUID(uuidString: remote.id) ?? UUID(),
            man: man, woman: woman,
            amount: remote.amount,
            note: remote.note ?? "",
        )
        self.status = BidStatus(rawValue: remote.status) ?? .pending
        self.gilded = remote.gilded
        self.insured = remote.insured
        self.isWhisper = remote.isWhisper
        self.promptRef = remote.promptRef
    }
}

/// Which endpoint a `RemoteBid` came from, so the adapter knows which side
/// of the record is "me."
enum RemoteBidDirection {
    case inbox     // I'm the lot; peer is the bidder
    case outbox    // I'm the bidder; peer is the lot
}

// MARK: - RemotePeer → Profile

extension Profile {
    /// Build a minimal local `Profile` from the embedded peer snapshot the
    /// matching Worker ships with each bid row. If the peer hasn't set a
    /// profile yet (`RemotePeer.name == nil`), we still render a placeholder
    /// so an inbox row doesn't crash — same "Someone" convention the Worker
    /// uses in push copy.
    init(fromRemotePeer peer: RemotePeer?, fallbackId: String, role: Role) {
        let id = UUID(uuidString: peer?.id ?? fallbackId) ?? UUID()
        self.init(
            id: id,
            name: peer?.name ?? "Someone",
            age: 0,               // not needed on the row; peer detail fetches profile
            role: role,
            location: "",
            bio: "",
            hue: peer?.hue ?? 0.6,
        )
        self.verified = peer?.isVerified ?? false
        if let a = peer?.archetype { self.archetype = Archetype(fromRemoteString: a) }
    }
}
