import Foundation

// Pure domain models — no SwiftUI/UIKit imports. Codable for the API layer.

struct User: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var handle: String          // community identity, e.g. "@ironbro"
    var displayName: String     // social identity (optional real name)
    var avatarURL: URL?
    var broCred: Int            // combined post + comment karma
    var isOnline: Bool = false
    var lastActiveAt: Date? = nil

    init(id: UUID, handle: String, displayName: String, avatarURL: URL?, broCred: Int,
         isOnline: Bool = false, lastActiveAt: Date? = nil) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.broCred = broCred
        self.isOnline = isOnline
        self.lastActiveAt = lastActiveAt
    }

    // Custom decoding so older/server payloads missing `isOnline`/`lastActiveAt`
    // (added after launch) fall back to their defaults instead of failing to
    // decode — synthesized Decodable doesn't apply property defaults to
    // missing keys, only the synthesized memberwise initializer does.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        handle = try container.decode(String.self, forKey: .handle)
        displayName = try container.decode(String.self, forKey: .displayName)
        avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        broCred = try container.decode(Int.self, forKey: .broCred)
        isOnline = try container.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
        lastActiveAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveAt)
    }
}

struct Community: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String            // "Iron Bro-hood"
    var slug: String            // "fitness"
    var memberCount: Int
    var iconURL: URL?
    var isJoined: Bool
    /// You moderate this Bro-hood — gates the mod queue and pin/lock/ban actions.
    var isModerator: Bool = false
    /// 18+ content (e.g. heavy training injuries, NSFW recovery talk) — gates
    /// a one-time age confirmation before joining.
    var isMature: Bool = false

    init(id: UUID, name: String, slug: String, memberCount: Int, iconURL: URL?,
         isJoined: Bool, isModerator: Bool = false, isMature: Bool = false) {
        self.id = id
        self.name = name
        self.slug = slug
        self.memberCount = memberCount
        self.iconURL = iconURL
        self.isJoined = isJoined
        self.isModerator = isModerator
        self.isMature = isMature
    }

    // See User.init(from:) — `isModerator`/`isMature` postdate some payloads, so missing
    // keys fall back to the default rather than failing to decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decode(String.self, forKey: .slug)
        memberCount = try container.decode(Int.self, forKey: .memberCount)
        iconURL = try container.decodeIfPresent(URL.self, forKey: .iconURL)
        isJoined = try container.decode(Bool.self, forKey: .isJoined)
        isModerator = try container.decodeIfPresent(Bool.self, forKey: .isModerator) ?? false
        isMature = try container.decodeIfPresent(Bool.self, forKey: .isMature) ?? false
    }
}

struct Post: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var author: User
    var community: Community?    // nil = posted to the social feed
    var title: String?
    var body: String
    var imageURL: URL?
    var score: Int
    var commentCount: Int
    var createdAt: Date
    var myVote: VoteValue
    /// Facebook-style reactions, used by social posts (community posts use votes).
    var reactions: ReactionSummary = .empty
    /// Reddit-style awards given to this post, keyed by kind.
    var awards: [AwardKind: Int] = [:]
    /// Mod-pinned to the top of its Bro-hood.
    var isPinned: Bool = false
    /// Mod-locked — no new comments, existing ones stay visible.
    var isLocked: Bool = false
    /// Bookmarked by the current user — surfaced in the Saved posts list.
    var isSaved: Bool = false

    /// Distinguishes the two halves of the hybrid feed for the UI.
    var origin: Origin { community == nil ? .social : .community }
    enum Origin { case social, community }

    var awardCount: Int { awards.values.reduce(0, +) }
}

/// Reddit-style awards. Cosmetic recognition bought with coins.
enum AwardKind: String, Codable, CaseIterable, Hashable, Sendable {
    case champ, solid, bigBrain

    var emoji: String {
        switch self {
        case .champ: "🏆"
        case .solid: "⭐️"
        case .bigBrain: "🧠"
        }
    }

    var label: String {
        switch self {
        case .champ: "Champ"
        case .solid: "Solid"
        case .bigBrain: "Big Brain"
        }
    }

    /// Coin cost to give the award.
    var cost: Int {
        switch self {
        case .champ: 300
        case .solid: 100
        case .bigBrain: 150
        }
    }
}

/// Wire-friendly vote value (the UI maps this to `VoteDirection`).
enum VoteValue: Int, Codable, Sendable {
    case down = -1, none = 0, up = 1
}

/// The MetaBro reaction set — a pro-social spin on Facebook's reactions.
/// `emoji`/`label` live on the model; the tint is a UI concern (see extensions).
enum ReactionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case respect, strong, lol, like, sad, angry

    var emoji: String {
        switch self {
        case .respect: "🤝"
        case .strong: "💪"
        case .lol: "😂"
        case .like: "👍"
        case .sad: "😢"
        case .angry: "😤"
        }
    }

    var label: String {
        switch self {
        case .respect: "Respect"
        case .strong: "Strong"
        case .lol: "LOL"
        case .like: "Like"
        case .sad: "Sad"
        case .angry: "Angry"
        }
    }
}

/// Aggregated reactions for a post plus the current user's own reaction.
struct ReactionSummary: Codable, Hashable, Sendable {
    var counts: [ReactionKind: Int]
    var mine: ReactionKind?

    static let empty = ReactionSummary(counts: [:], mine: nil)

    var total: Int { counts.values.reduce(0, +) }

    /// The most-used reactions, highest first — for the summary row.
    var top: [ReactionKind] {
        counts.filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }

    /// Apply a tap on `reaction`; tapping your current reaction clears it.
    /// Keeps counts and `mine` consistent. Pure — safe for optimistic updates.
    mutating func apply(_ reaction: ReactionKind?) {
        let target = (reaction == mine) ? nil : reaction
        if let prev = mine, let c = counts[prev] {
            counts[prev] = c > 1 ? c - 1 : nil
        }
        if let target {
            counts[target, default: 0] += 1
        }
        mine = target
    }
}

/// A comment in a Reddit-style tree. Stored flat with a `parentID` so it
/// serializes cleanly over the wire; the UI assembles the tree for display.
struct Comment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let postID: UUID
    let parentID: UUID?         // nil = top-level
    var author: User
    var body: String
    var score: Int
    var createdAt: Date
    var myVote: VoteValue
    var isOP: Bool              // author is the post's author — highlighted in UI
}

/// A comment plus its computed nesting depth, ready to render in a flat list.
struct ThreadedComment: Identifiable, Hashable, Sendable {
    let comment: Comment
    let depth: Int
    var id: UUID { comment.id }
}

/// What onboarding hands to `AuthService` to claim a handle and identity.
/// `handle` is the raw value with no leading "@" — that's added when the
/// `User` is created, matching how handles render everywhere else.
struct OnboardingDraft: Sendable {
    var handle: String
    var displayName: String

    /// Reddit-style handle rules: lowercase letters/digits/underscores,
    /// starting with a letter, 3–20 characters.
    var isValid: Bool {
        let h = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameOK = !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard h.count >= 3, h.count <= 20, nameOK else { return false }
        return h.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil
    }
}

/// What the composer hands to the service when creating a post. `community`
/// is nil for a social post, set for a Bro-hood post.
struct PostDraft: Sendable {
    var title: String?
    var body: String
    var community: Community?

    var isValid: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The current user's profile: identity + reputation split + memberships +
/// authored posts. `broCred` is the combined karma shown on the profile.
struct Profile: Identifiable, Sendable {
    var user: User
    var postKarma: Int
    var commentKarma: Int
    var joinedCommunities: [Community]
    var posts: [Post]

    var id: UUID { user.id }
    var broCred: Int { postKarma + commentKarma }
}

// MARK: - Messaging

/// Delivery state of an outgoing message (Facebook-style receipts).
enum MessageStatus: Int, Codable, Sendable {
    case sending, sent, delivered, read
}

struct Message: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let conversationID: UUID
    var sender: User
    var text: String
    var sentAt: Date
    var status: MessageStatus
    var voiceNoteDuration: TimeInterval? = nil

    var isMine: Bool { sender.id == Session.me.id }
    var isVoiceNote: Bool { voiceNoteDuration != nil }
}

/// A DM thread. `participants` holds the *other* people (not you), so a 1:1
/// shows their name and a group shows its title.
struct Conversation: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var participants: [User]
    var isGroup: Bool
    var title: String?
    var lastMessage: String
    var lastActivity: Date
    var unreadCount: Int

    var displayTitle: String {
        title ?? participants.first?.displayName ?? "Chat"
    }
}

// MARK: - Safety & moderation

/// What's being reported, blocked-from, or moderated. Drives routing in the
/// mod queue and which detail screen a tap on a report opens.
enum ReportedContentKind: String, Codable, Hashable, Sendable {
    case post, comment, profile, message
}

/// Reason picked in the report sheet — mirrors the standard Reddit/Facebook set.
enum ReportReason: String, Codable, CaseIterable, Hashable, Sendable {
    case spam, harassment, hatefulContent, violence, misinformation, other

    var label: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Harassment or bullying"
        case .hatefulContent: "Hateful content"
        case .violence: "Violence or dangerous behavior"
        case .misinformation: "Misinformation"
        case .other: "Something else"
        }
    }
}

enum ReportStatus: String, Codable, Hashable, Sendable {
    case pending, removed, approved
}

/// A user-filed report, triaged by community mods in the queue.
struct Report: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: ReportedContentKind
    var targetID: UUID
    /// Short snippet of the reported content/profile, shown in the queue
    /// without needing to fetch the full post/comment/message.
    var preview: String
    var reportedUser: User
    var community: Community?
    var reason: ReportReason
    var details: String?
    var createdAt: Date
    var status: ReportStatus
}

// MARK: - Friends

/// What triggered a notification, driving its icon and how a tap routes.
enum NotificationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case friendRequest, friendAccepted, reaction, vote, comment, award, mention

    var systemImage: String {
        switch self {
        case .friendRequest: "person.badge.plus"
        case .friendAccepted: "person.2.fill"
        case .reaction: "face.smiling"
        case .vote: "arrow.up.circle.fill"
        case .comment: "bubble.left.fill"
        case .award: "trophy.fill"
        case .mention: "at"
        }
    }
}

/// A single activity item in the notifications feed. `post` is the deep-link
/// target when the notification is about a post/comment; nil for friend
/// activity, which only concerns `actor`.
struct AppNotification: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: NotificationKind
    var actor: User
    var message: String
    var post: Post?
    var createdAt: Date
    var isRead: Bool
}

// MARK: - Stories

/// An ephemeral Facebook-style story. `accentIndex` seeds the UI gradient so the
/// model stays free of SwiftUI types.
struct Story: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var author: User
    var caption: String
    var createdAt: Date
    var seen: Bool
    var accentIndex: Int
}

// MARK: - Events

/// The current user's RSVP to an event. `none` renders as "Interested?" —
/// any other value is a committed answer.
enum RSVPStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case none, going, interested, notGoing

    var label: String {
        switch self {
        case .none: "RSVP"
        case .going: "Going"
        case .interested: "Interested"
        case .notGoing: "Not going"
        }
    }
}

/// A real-world meetup spun up by a Bro-hood (pickup games, watch parties,
/// in-person hangs) — the bridge from interest graph to social graph.
struct Event: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var details: String
    var community: Community?
    var host: User
    var location: String
    var startDate: Date
    var attendeeCount: Int
    var myRSVP: RSVPStatus = .none

    var isPast: Bool { startDate < .now }

    init(id: UUID, title: String, details: String, community: Community?, host: User,
         location: String, startDate: Date, attendeeCount: Int, myRSVP: RSVPStatus = .none) {
        self.id = id
        self.title = title
        self.details = details
        self.community = community
        self.host = host
        self.location = location
        self.startDate = startDate
        self.attendeeCount = attendeeCount
        self.myRSVP = myRSVP
    }

    // See User.init(from:) — `myRSVP` postdates some payloads, so a missing key
    // falls back to `.none` rather than failing to decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        details = try container.decode(String.self, forKey: .details)
        community = try container.decodeIfPresent(Community.self, forKey: .community)
        host = try container.decode(User.self, forKey: .host)
        location = try container.decode(String.self, forKey: .location)
        startDate = try container.decode(Date.self, forKey: .startDate)
        attendeeCount = try container.decode(Int.self, forKey: .attendeeCount)
        myRSVP = try container.decodeIfPresent(RSVPStatus.self, forKey: .myRSVP) ?? .none
    }
}

/// What the create-event sheet hands to the service.
struct EventDraft: Sendable {
    var title: String
    var details: String
    var community: Community?
    var location: String
    var startDate: Date

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
