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
