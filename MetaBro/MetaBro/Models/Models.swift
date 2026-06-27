import Foundation

// Pure domain models — no SwiftUI/UIKit imports. Codable for the API layer.

struct User: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var handle: String          // community identity, e.g. "@ironbro"
    var displayName: String     // social identity (optional real name)
    var avatarURL: URL?
    var broCred: Int            // combined post + comment karma
}

struct Community: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String            // "Iron Bro-hood"
    var slug: String            // "fitness"
    var memberCount: Int
    var iconURL: URL?
    var isJoined: Bool
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

    var isMine: Bool { sender.id == Session.me.id }
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
