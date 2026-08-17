import Foundation

/// Backend-backed feed. Reads through `PostDTO`/`FeedPageDTO`; writes are
/// fire-and-forget mutations (the UI already updated optimistically).
struct LiveFeedService: FeedService {
    let client: APIClient

    func feed(sort: FeedSort, cursor: String?) async throws -> FeedPage {
        try await client.send(API.feed(sort: sort, cursor: cursor), as: FeedPageDTO.self).toDomain()
    }

    func vote(postID: UUID, value: VoteValue) async throws {
        try await client.send(API.vote(postID: postID, .init(value: value.rawValue)))
    }

    func react(postID: UUID, reaction: ReactionKind?) async throws {
        try await client.send(API.react(postID: postID, .init(reaction: reaction?.rawValue)))
    }

    func giveAward(postID: UUID, award: AwardKind) async throws {
        try await client.send(API.award(postID: postID, .init(award: award.rawValue)))
    }

    func createPost(_ draft: PostDraft) async throws -> Post {
        let body = CreatePostRequest(title: draft.title, body: draft.body,
                                     communityID: draft.community?.id)
        return try await client.send(API.createPost(body), as: PostDTO.self).toDomain()
    }

    func posts(by userID: UUID) async throws -> [Post] {
        try await client.send(API.postsByUser(userID), as: [PostDTO].self).map { $0.toDomain() }
    }
}
