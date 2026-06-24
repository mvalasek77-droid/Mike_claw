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
    let messagingService: MessagingService
    let storyService: StoryService
    let bugReportService: BugReportService

    init(
        feedService: FeedService,
        commentService: CommentService,
        communityService: CommunityService,
        profileService: ProfileService,
        searchService: SearchService,
        messagingService: MessagingService,
        storyService: StoryService,
        bugReportService: BugReportService
    ) {
        self.feedService = feedService
        self.commentService = commentService
        self.communityService = communityService
        self.profileService = profileService
        self.searchService = searchService
        self.messagingService = messagingService
        self.storyService = storyService
        self.bugReportService = bugReportService
    }

    /// Resolves the dependency graph from configuration: a live backend when
    /// one is configured, in-memory mocks otherwise. Either way Profile and
    /// Search compose from the chosen feed + community services, so they follow
    /// the same source of truth automatically.
    static func resolve(config: BackendConfig = BackendConfig()) -> AppContainer {
        if let baseURL = config.resolvedBaseURL {
            return live(baseURL: baseURL)
        }
        return mocks()
    }

    /// Backwards-compatible entry point used by the app.
    static func live() -> AppContainer { resolve() }

    private static func live(baseURL: URL) -> AppContainer {
        let client = LiveAPIClient(baseURL: baseURL)
        let feed = LiveFeedService(client: client)
        let communities = LiveCommunityService(client: client)
        return AppContainer(
            feedService: feed,
            commentService: LiveCommentService(client: client),
            communityService: communities,
            profileService: MockProfileService(feedService: feed, communityService: communities),
            searchService: MockSearchService(feedService: feed, communityService: communities),
            messagingService: LiveMessagingService(client: client),
            storyService: LiveStoryService(client: client),
            bugReportService: LiveBugReportService(client: client)
        )
    }

    /// In-memory wiring for previews, tests, and offline demo. The feed and
    /// community services are shared instances so the composer, profile, and
    /// search all reflect the same evolving state.
    private static func mocks() -> AppContainer {
        let feed = MockFeedService()
        let communities = MockCommunityService()
        return AppContainer(
            feedService: feed,
            commentService: MockCommentService(),
            communityService: communities,
            profileService: MockProfileService(feedService: feed, communityService: communities),
            searchService: MockSearchService(feedService: feed, communityService: communities),
            messagingService: MockMessagingService(),
            storyService: MockStoryService(),
            bugReportService: MockBugReportService()
        )
    }
}
