import Testing
import Foundation
@testable import MetaBro

/// Unit tests for the feed loop: loading, empty, error, optimistic voting,
/// and rollback. Run against deterministic mock services — no network.
@MainActor
struct FeedViewModelTests {

    @Test func loadsPostsIntoLoadedState() async {
        let model = FeedViewModel(service: MockFeedService())
        await model.load()
        guard case .loaded(let posts) = model.state else {
            Issue.record("expected .loaded, got \(model.state)")
            return
        }
        #expect(posts.count == 2)
    }

    @Test func emptyServiceProducesEmptyState() async {
        let model = FeedViewModel(service: MockFeedService(posts: []))
        await model.load()
        #expect(model.state == .empty)
    }

    @Test func failingServiceProducesErrorState() async {
        let model = FeedViewModel(service: FailingFeedService())
        await model.load()
        guard case .error = model.state else {
            Issue.record("expected .error, got \(model.state)")
            return
        }
    }

    @Test func upvoteIncrementsScoreOptimistically() async {
        let model = FeedViewModel(service: MockFeedService())
        await model.load()
        guard case .loaded(let posts) = model.state, let first = posts.first else {
            Issue.record("no posts"); return
        }
        let before = first.score
        await model.vote(on: first, value: .up)

        guard case .loaded(let after) = model.state,
              let updated = after.first(where: { $0.id == first.id }) else {
            Issue.record("post vanished"); return
        }
        #expect(updated.score == before + 1)
        #expect(updated.myVote == .up)
    }

    @Test func failedVoteRollsBack() async {
        let model = FeedViewModel(service: VoteFailingService())
        await model.load()
        guard case .loaded(let posts) = model.state, let first = posts.first else {
            Issue.record("no posts"); return
        }
        let before = first.score
        await model.vote(on: first, value: .up)

        guard case .loaded(let after) = model.state,
              let updated = after.first(where: { $0.id == first.id }) else {
            Issue.record("post vanished"); return
        }
        #expect(updated.score == before)        // rolled back
        #expect(updated.myVote == first.myVote)
    }
}

// MARK: - Test doubles

private struct FailingFeedService: FeedService {
    func feed(sort: FeedSort, cursor: String?) async throws -> FeedPage {
        throw APIError.offline
    }
    func vote(postID: UUID, value: VoteValue) async throws {}
    func createPost(_ draft: PostDraft) async throws -> Post { throw APIError.offline }
    func posts(by userID: UUID) async throws -> [Post] { [] }
}

/// Loads fine, but every vote fails — exercises the rollback path.
private struct VoteFailingService: FeedService {
    func feed(sort: FeedSort, cursor: String?) async throws -> FeedPage {
        FeedPage(posts: MockFeedService.seed(), nextCursor: nil)
    }
    func vote(postID: UUID, value: VoteValue) async throws {
        throw APIError.server(status: 500)
    }
    func createPost(_ draft: PostDraft) async throws -> Post { throw APIError.server(status: 500) }
    func posts(by userID: UUID) async throws -> [Post] { [] }
}
