import SwiftUI

/// Lightweight dependency container. Services are resolved here and injected
/// into the environment, so features depend on protocols, never concrete types.
@MainActor
@Observable
final class AppContainer {
    let feedService: FeedService

    init(feedService: FeedService) {
        self.feedService = feedService
    }

    /// Default wiring. Swap `MockFeedService` for a live service once the
    /// backend is reachable (gated behind a feature flag / build config).
    static func live() -> AppContainer {
        AppContainer(feedService: MockFeedService())
    }
}
