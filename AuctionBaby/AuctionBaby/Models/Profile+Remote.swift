import Foundation

// MARK: - PublicProfile → Profile adapter

extension Profile {
    /// Convert a server-side `PublicProfile` (from the auth Worker's floor
    /// feed or peer lookup) into the local `Profile` shape the UI reads.
    /// Slice 4b1 uses this to render real signed-in users on the floor
    /// through the same code paths the sim uses — no view branching.
    ///
    /// The server-side `userId` is a UUID string; we preserve it as
    /// `Profile.id` so a bid placed on this profile can round-trip back to
    /// the matching Worker (its `POST /bids` takes the same UUID as `lotId`).
    /// A malformed userId falls back to a fresh UUID, which just means the
    /// server can't route the bid — safer than crashing.
    ///
    /// Fields NOT carried over (default to their `Profile` defaults):
    /// - past bids / reviews / credit history (derived from server data
    ///   that later slices will surface separately)
    /// - `isCopycat` (real signed-in users are never copycats)
    init(from remote: PublicProfile) {
        let id = UUID(uuidString: remote.userId) ?? UUID()
        let role = Role(rawValue: remote.role) ?? .woman
        self.init(
            id: id,
            name: remote.name,
            age: remote.age ?? 0,
            role: role,
            location: remote.location ?? "",
            bio: remote.bio ?? "",
            hue: remote.hue,
            remotePhotoURLs: remote.photos.map(\.url),
            prompts: remote.prompts.map { Prompt(question: $0.question, answer: $0.answer) },
            interests: remote.interests
        )
        self.startingBid = remote.startingBid
        self.openingBidScript = remote.openingBidScript
        self.archetype = Archetype(fromRemoteString: remote.archetype)
        self.verified = remote.isVerified
    }
}

// MARK: - Archetype string ↔ enum bridge

extension Archetype {
    /// Reverse of the client's `String(describing: profile.archetype)` upload
    /// — the auth Worker stores archetype as the lowercase case name. Unknown
    /// or absent strings map to `.none` (safer than crashing on a schema
    /// mismatch between an old client and a newer server or vice versa).
    init(fromRemoteString s: String?) {
        guard let s, !s.isEmpty else { self = .none; return }
        switch s {
        case "none":         self = .none
        case "goodGuy":      self = .goodGuy
        case "inAndOut":     self = .inAndOut
        case "whyNot":       self = .whyNot
        case "goodJob":      self = .goodJob
        case "inheritance":  self = .inheritance
        case "influencer":   self = .influencer
        case "ferrari":      self = .ferrari
        case "trillionaire": self = .trillionaire
        default:             self = .none
        }
    }
}
