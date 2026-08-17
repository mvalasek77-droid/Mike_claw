import Foundation

/// Wire representation of a post. Reactions and awards travel as arrays of
/// {kind, count} (clean JSON), unlike the dictionary-keyed domain model — so a
/// DTO + mapping layer keeps both sides idiomatic.
struct PostDTO: Decodable {
    let id: UUID
    let author: User
    let community: Community?
    let title: String?
    let body: String
    let imageURL: URL?
    let score: Int
    let commentCount: Int
    let createdAt: Date
    let myVote: Int
    let reactions: [CountDTO]
    let myReaction: String?
    let awards: [CountDTO]

    struct CountDTO: Decodable { let kind: String; let count: Int }

    func toDomain() -> Post {
        var reactionCounts: [ReactionKind: Int] = [:]
        for entry in reactions {
            if let kind = ReactionKind(rawValue: entry.kind) { reactionCounts[kind] = entry.count }
        }
        var awardCounts: [AwardKind: Int] = [:]
        for entry in awards {
            if let kind = AwardKind(rawValue: entry.kind) { awardCounts[kind] = entry.count }
        }
        return Post(
            id: id,
            author: author,
            community: community,
            title: title,
            body: body,
            imageURL: imageURL,
            score: score,
            commentCount: commentCount,
            createdAt: createdAt,
            myVote: VoteValue(rawValue: myVote) ?? .none,
            reactions: ReactionSummary(
                counts: reactionCounts,
                mine: myReaction.flatMap(ReactionKind.init(rawValue:))
            ),
            awards: awardCounts
        )
    }
}

/// A page of feed results from the server.
struct FeedPageDTO: Decodable {
    let posts: [PostDTO]
    let nextCursor: String?

    func toDomain() -> FeedPage {
        FeedPage(posts: posts.map { $0.toDomain() }, nextCursor: nextCursor)
    }
}
