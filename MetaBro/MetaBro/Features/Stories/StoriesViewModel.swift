import SwiftUI

/// Loads the stories rail and tracks which have been seen. Quietly no-ops on
/// failure — stories are a non-critical garnish on top of the feed.
@MainActor
@Observable
final class StoriesViewModel {
    private(set) var stories: [Story] = []
    private let service: StoryService

    init(service: StoryService) {
        self.service = service
    }

    func load() async {
        stories = (try? await service.stories()) ?? []
    }

    func markSeen(_ id: UUID) async {
        guard let idx = stories.firstIndex(where: { $0.id == id }), !stories[idx].seen else { return }
        stories[idx].seen = true
        try? await service.markSeen(id)
    }
}
