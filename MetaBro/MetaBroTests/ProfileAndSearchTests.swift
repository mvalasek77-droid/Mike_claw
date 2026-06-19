import Testing
import Foundation
@testable import MetaBro

@MainActor
struct ProfileAndSearchTests {

    // MARK: Profile

    private func profileService() -> ProfileService {
        MockProfileService(feedService: MockFeedService(),
                           communityService: MockCommunityService())
    }

    @Test func profileLoadsWithKarmaAndPosts() async {
        let model = ProfileViewModel(service: profileService())
        await model.load()
        guard case .loaded(let profile) = model.state else {
            Issue.record("expected .loaded, got \(model.state)"); return
        }
        #expect(profile.user.id == Session.me.id)
        #expect(profile.broCred == profile.postKarma + profile.commentKarma)
        // Seed includes one post authored by the current user.
        #expect(profile.posts.allSatisfy { $0.author.id == Session.me.id })
        #expect(!profile.posts.isEmpty)
        #expect(profile.joinedCommunities.allSatisfy(\.isJoined))
    }

    @Test func profileReflectsNewlyCreatedPost() async {
        let feed = MockFeedService()
        let service = MockProfileService(feedService: feed,
                                         communityService: MockCommunityService())
        _ = try? await feed.createPost(PostDraft(title: nil, body: "Fresh post", community: nil))

        let model = ProfileViewModel(service: service)
        await model.load()
        guard case .loaded(let profile) = model.state else { Issue.record("not loaded"); return }
        #expect(profile.posts.contains { $0.body == "Fresh post" })
    }

    // MARK: Search

    private func searchService() -> SearchService {
        MockSearchService(feedService: MockFeedService(),
                          communityService: MockCommunityService())
    }

    @Test func emptyQueryReturnsIdle() async {
        let model = SearchViewModel(service: searchService())
        model.query("   ")
        #expect(model.state == .idle)
    }

    @Test func matchingQueryReturnsResults() async {
        let model = SearchViewModel(service: searchService())
        model.query("Iron")
        // Wait out the debounce + service latency.
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard case .results(let results) = model.state else {
            Issue.record("expected .results, got \(model.state)"); return
        }
        #expect(results.communities.contains { $0.name.localizedCaseInsensitiveContains("Iron") })
    }

    @Test func nonsenseQueryReturnsEmpty() async {
        let model = SearchViewModel(service: searchService())
        model.query("zzqqxx")
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard case .empty = model.state else {
            Issue.record("expected .empty, got \(model.state)"); return
        }
    }
}
