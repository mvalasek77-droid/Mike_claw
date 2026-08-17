import Testing
import Foundation
@testable import MetaBro

/// Coverage for this slice: saved-posts bookmarking, view history, the feed's
/// optimistic save toggle, and the caught-up marker computed at load time.
@MainActor
struct SavedServiceTests {

    @Test func savedPostsReflectsSetSaved() async throws {
        let feed = MockFeedService()
        let service = MockSavedService(feedService: feed)
        let target = try await feed.feed(sort: .new, cursor: nil).posts[0]

        try await service.setSaved(postID: target.id, saved: true)
        let saved = try await service.savedPosts()
        #expect(saved.contains { $0.id == target.id && $0.isSaved })

        try await service.setSaved(postID: target.id, saved: false)
        let afterUnsave = try await service.savedPosts()
        #expect(!afterUnsave.contains { $0.id == target.id })
    }

    @Test func mostRecentlySavedComesFirst() async throws {
        let feed = MockFeedService()
        let service = MockSavedService(feedService: feed)
        let posts = try await feed.feed(sort: .new, cursor: nil).posts

        try await service.setSaved(postID: posts[0].id, saved: true)
        try await service.setSaved(postID: posts[1].id, saved: true)

        let saved = try await service.savedPosts()
        #expect(saved.first?.id == posts[1].id)
    }
}

@MainActor
struct HistoryServiceTests {

    @Test func recordViewMovesPostToFront() async throws {
        let service = MockHistoryService()
        let a = UUID()
        let b = UUID()

        try await service.recordView(postID: a)
        try await service.recordView(postID: b)
        try await service.recordView(postID: a) // re-viewing moves it back to front

        let ids = try await service.viewedPostIDs()
        #expect(ids == [a, b])
    }
}

@MainActor
struct FeedSaveAndHistoryTests {

    @Test func toggleSaveIsOptimisticAndPersists() async {
        let feed = MockFeedService()
        let saved = MockSavedService(feedService: feed)
        let model = FeedViewModel(service: feed, savedService: saved, historyService: MockHistoryService())
        await model.load()

        guard case .loaded(let posts) = model.state, let first = posts.first else {
            Issue.record("no posts"); return
        }
        #expect(!first.isSaved)
        await model.toggleSave(first)

        guard case .loaded(let after) = model.state,
              let updated = after.first(where: { $0.id == first.id }) else {
            Issue.record("post vanished"); return
        }
        #expect(updated.isSaved)

        let persisted = try? await saved.savedPosts()
        #expect(persisted?.contains { $0.id == first.id } == true)
    }

    @Test func caughtUpMarkerPointsAtFirstViewedPost() async {
        let feed = MockFeedService()
        let history = MockHistoryService()
        let model = FeedViewModel(service: feed, savedService: MockSavedService(feedService: feed),
                                  historyService: history)
        await model.load()
        #expect(model.caughtUpMarkerID == nil)

        guard case .loaded(let posts) = model.state, let secondPost = posts.dropFirst().first else {
            Issue.record("need at least two posts"); return
        }
        await model.markViewed(secondPost)
        await model.load()

        #expect(model.caughtUpMarkerID == secondPost.id)
    }
}

@MainActor
struct SavedViewModelTests {

    @Test func unsaveRemovesPostFromList() async throws {
        let feed = MockFeedService()
        let service = MockSavedService(feedService: feed)
        let target = try await feed.feed(sort: .new, cursor: nil).posts[0]
        try await service.setSaved(postID: target.id, saved: true)

        let model = SavedViewModel(service: service)
        await model.load()
        guard case .loaded(let posts) = model.state, let first = posts.first else {
            Issue.record("expected the saved post"); return
        }
        await model.unsave(first)

        #expect(model.state == .empty)
    }
}
