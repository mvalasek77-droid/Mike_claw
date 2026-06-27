import Foundation

/// Bookmarking: save/unsave any post and list everything you've saved.
protocol SavedService: Sendable {
    func setSaved(postID: UUID, saved: Bool) async throws
    /// Every post you've saved, newest-saved first.
    func savedPosts() async throws -> [Post]
}

/// Deterministic in-memory bookmarks for previews, tests, and offline demo.
/// Saved IDs are tracked here; the actual `Post` content is sourced from
/// `feedService` so the saved list always reflects the latest score/votes/etc.
actor MockSavedService: SavedService {
    private var savedIDsInOrder: [UUID] = []
    private let feedService: FeedService

    init(feedService: FeedService) {
        self.feedService = feedService
    }

    func setSaved(postID: UUID, saved: Bool) async throws {
        savedIDsInOrder.removeAll { $0 == postID }
        if saved { savedIDsInOrder.insert(postID, at: 0) }
    }

    func savedPosts() async throws -> [Post] {
        let page = try await feedService.feed(sort: .new, cursor: nil)
        let byID = Dictionary(uniqueKeysWithValues: page.posts.map { ($0.id, $0) })
        return savedIDsInOrder.compactMap { id in
            guard var post = byID[id] else { return nil }
            post.isSaved = true
            return post
        }
    }
}
