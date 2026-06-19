import SwiftUI

/// Lightweight dependency container. Services are resolved here and injected
/// via initializers, so features depend on protocols, never concrete types.
@MainActor
@Observable
final class AppContainer {
    let feedService: FeedService
    let commentService: CommentService
    let communityService: CommunityService
    let profileService: ProfileService
    let searchService: SearchService

    init(
        feedService: FeedService,
        commentService: CommentService,
        communityService: CommunityService,
        profileService: ProfileService,
        searchService: SearchService
    ) {
        self.feedService = feedService
        self.commentService = commentService
        self.communityService = communityService
        self.profileService = profileService
        self.searchService = searchService
    }

    /// Default wiring. Swap the mocks for live services once the backend is
    /// reachable (gated behind a feature flag / build config). The feed and
    /// community services are shared instances so the composer, profile, and
    /// search all reflect the same evolving state.
    static func live() -> AppContainer {
        let feed = MockFeedService()
        let communities = MockCommunityService()
        return AppContainer(
            feedService: feed,
            commentService: MockCommentService(),
            communityService: communities,
            profileService: MockProfileService(feedService: feed, communityService: communities),
            searchService: MockSearchService(feedService: feed, communityService: communities)
        )
    }
}
