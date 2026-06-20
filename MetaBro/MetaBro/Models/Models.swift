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

    /// Distinguishes the two halves of the hybrid feed for the UI.
    var origin: Origin { community == nil ? .social : .community }
    enum Origin { case social, community }
}

/// Wire-friendly vote value (the UI maps this to `VoteDirection`).
enum VoteValue: Int, Codable, Sendable {
    case down = -1, none = 0, up = 1
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
