import SwiftUI

/// Lightweight dependency container. Services are resolved here and injected
/// via initializers, so features depend on protocols, never concrete types.
@MainActor
@Observable
final class AppContainer {
    let feedService: FeedService
    let commentService: CommentService
    let communityService: CommunityService

    init(
        feedService: FeedService,
        commentService: CommentService,
        communityService: CommunityService
    ) {
        self.feedService = feedService
        self.commentService = commentService
        self.communityService = communityService
    }

    /// Default wiring. Swap the mocks for live services once the backend is
    /// reachable (gated behind a feature flag / build config).
    static func live() -> AppContainer {
        AppContainer(
            feedService: MockFeedService(),
            commentService: MockCommentService(),
            communityService: MockCommunityService()
        )
    }
}
