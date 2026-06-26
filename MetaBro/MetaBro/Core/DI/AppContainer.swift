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
    let authService: AuthService

    init(
        feedService: FeedService,
        commentService: CommentService,
        communityService: CommunityService,
        profileService: ProfileService,
        searchService: SearchService,
        messagingService: MessagingService,
        storyService: StoryService,
        bugReportService: BugReportService,
        authService: AuthService
    ) {
        self.feedService = feedService
        self.commentService = commentService
        self.communityService = communityService
        self.profileService = profileService
        self.searchService = searchService
        self.messagingService = messagingService
        self.storyService = storyService
        self.bugReportService = bugReportService
        self.authService = authService
    }

    /// Resolves the dependency graph from configuration: a live backend when
    /// one is configured, in-memory mocks otherwise. Either way Profile and
    /// Search compose from the chosen feed + community services, so they follow
    /// the same source of truth automatically.
    ///
    /// Call this only once an identity is established (after `makeAuthService()`
    /// has restored or onboarded a session) — mock seed data (e.g. "your" demo
    /// post) is authored by whoever `Session.me` is at the moment it's created.
    static func resolve(config: BackendConfig = BackendConfig()) -> AppContainer {
        if let baseURL = config.resolvedBaseURL {
            return live(baseURL: baseURL)
        }
        return mocks()
    }

    /// Builds just the auth service, so the launch flow can restore/establish
    /// an identity *before* the rest of the graph (and its mock seed data) is
    /// built from `resolve()`.
    static func makeAuthService(config: BackendConfig = BackendConfig()) -> AuthService {
        if let baseURL = config.resolvedBaseURL {
            return LiveAuthService(client: LiveAPIClient(baseURL: baseURL))
        }
        return MockAuthService()
    }

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
            bugReportService: LiveBugReportService(client: client),
            authService: LiveAuthService(client: client)
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
            bugReportService: MockBugReportService(),
            authService: MockAuthService()
        )
    }
}
