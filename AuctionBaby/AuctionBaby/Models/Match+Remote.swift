import Foundation

// MARK: - RemoteMatch → Match adapter (slice 4b1d)

extension Match {
    /// Convert a server-side `RemoteMatch` (from the matching Worker) into
    /// the local `Match` shape the UI reads. Preserves the server's match id
    /// as `Match.id` so a tap on a row can drive `/matches/:id/messages`
    /// straight from the local record.
    ///
    /// A `Match` embeds a full `Bid` on itself (so records survive independently
    /// of live rosters). We rebuild that Bid from the match record plus the
    /// peer snapshot — the same pattern used for the incoming/outgoing
    /// inboxes in slice 4b1b, symmetric direction.
    ///
    /// `messages` are NOT populated here — the list endpoint doesn't ship
    /// them (the chat view fetches them on demand via `fetchMatch`). They stay
    /// as an empty array until `AuctionStore.refreshRemoteMatch(_:matching:)`
    /// fills them in.
    init(from remote: RemoteMatch, mine: Profile) {
        // Am I the bidder (the man) on this match, or the lot?
        let myId = mine.id.uuidString.lowercased()
        let iAmBidder = remote.bidderId == myId
        let peerProfile = Profile(fromRemotePeer: remote.peer,
                                  fallbackId: iAmBidder ? remote.lotId : remote.bidderId,
                                  role: iAmBidder ? .woman : .man)
        let man = iAmBidder ? mine : peerProfile
        let woman = iAmBidder ? peerProfile : mine

        var bid = Bid(man: man, woman: woman, amount: remote.amount)
        bid.id = UUID(uuidString: remote.bidId) ?? UUID()
        bid.status = .accepted   // by construction — this bid was accepted to create the match

        self.init(
            id: UUID(uuidString: remote.id) ?? UUID(),
            bid: bid,
            messages: [],
            phase: MatchPhase(rawValue: remote.phase) ?? .chatting,
            manReviewedWoman: false, womanReviewedMan: false,
            spentAmount: nil,
            manConfirmedMet: false, womanConfirmedMet: false,
            seenByOther: false,
            expiresAt: remote.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            dateReserved: remote.reservedAt != nil,
            reservedAmountCents: remote.reservedAmountCents,
        )
    }
}

// MARK: - RemoteMessage → ChatMessage adapter

extension ChatMessage {
    /// Convert a server-side message into the local shape. `fromMe` is derived
    /// from whether the message's `fromId` matches the current user's id — we
    /// don't need to store it server-side.
    init(from remote: RemoteMessage, mineId: String) {
        let mine = remote.fromId == mineId
        self.init(
            id: UUID(uuidString: remote.id) ?? UUID(),
            fromMe: mine,
            text: remote.text,
            date: Date(timeIntervalSince1970: remote.createdAt / 1000),
            isSystem: false,
            reaction: remote.reaction,
        )
    }
}
