import Foundation

enum FeedSort: String, CaseIterable, Sendable {
    case hot, new, top
    var title: String { rawValue.capitalized }
}

/// A page of feed results with a cursor for infinite scroll.
struct FeedPage: Sendable {
    var posts: [Post]
    var nextCursor: String?
}

protocol FeedService: Sendable {
    func feed(sort: FeedSort, cursor: String?) async throws -> FeedPage
    func vote(postID: UUID, value: VoteValue) async throws
}

/// Deterministic in-memory service used for previews, tests, and offline demo.
/// Mirrors the live contract so the UI behaves identically against either.
actor MockFeedService: FeedService {
    private var posts: [Post]

    init(posts: [Post] = MockFeedService.seed()) {
        self.posts = posts
    }

    func feed(sort: FeedSort, cursor: String?) async throws -> FeedPage {
        // Simulate latency so loading states are exercised.
        try await Task.sleep(nanoseconds: 250_000_000)
        let sorted: [Post]
        switch sort {
        case .hot:  sorted = posts.sorted { $0.score > $1.score }
        case .new:  sorted = posts.sorted { $0.createdAt > $1.createdAt }
        case .top:  sorted = posts.sorted { $0.score > $1.score }
        }
        return FeedPage(posts: sorted, nextCursor: nil)
    }

    func vote(postID: UUID, value: VoteValue) async throws {
        guard let idx = posts.firstIndex(where: { $0.id == postID }) else { return }
        let old = posts[idx].myVote
        posts[idx].score += value.rawValue - old.rawValue
        posts[idx].myVote = value
    }

    static func seed() -> [Post] {
        let bro = User(id: UUID(), handle: "@ironbro", displayName: "Marcus",
                       avatarURL: nil, broCred: 4_820)
        let fitness = Community(id: UUID(), name: "Iron Bro-hood", slug: "fitness",
                                memberCount: 182_000, iconURL: nil, isJoined: true)
        return [
            Post(id: UUID(), author: bro, community: fitness,
                 title: "PSA: warm up your rotator cuffs, bros",
                 body: "Saved my bench after years of nagging pain. Here's the routine.",
                 imageURL: nil, score: 1_240, commentCount: 86,
                 createdAt: .now.addingTimeInterval(-3_600), myVote: .none),
            Post(id: UUID(), author: bro, community: nil,
                 title: nil,
                 body: "Pickup basketball this Saturday at Riverside. Who's in?",
                 imageURL: nil, score: 42, commentCount: 12,
                 createdAt: .now.addingTimeInterval(-7_200), myVote: .up),
        ]
    }
}
