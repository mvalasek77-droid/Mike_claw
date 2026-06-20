import Foundation

protocol StoryService: Sendable {
    func stories() async throws -> [Story]
    func markSeen(_ id: UUID) async throws
}

/// Deterministic in-memory stories for previews, tests, and offline demo.
actor MockStoryService: StoryService {
    private var store: [Story]

    init(stories: [Story] = MockStoryService.seed()) {
        self.store = stories
    }

    func stories() async throws -> [Story] {
        try await Task.sleep(nanoseconds: 150_000_000)
        // Unseen first, then by recency — mirrors how Stories rails are ordered.
        return store.sorted {
            $0.seen == $1.seen ? $0.createdAt > $1.createdAt : (!$0.seen && $1.seen)
        }
    }

    func markSeen(_ id: UUID) async throws {
        guard let idx = store.firstIndex(where: { $0.id == id }) else { return }
        store[idx].seen = true
    }

    static func seed() -> [Story] {
        let marcus = User(id: UUID(), handle: "@ironbro", displayName: "Marcus",
                          avatarURL: nil, broCred: 4_820)
        let dave = User(id: UUID(), handle: "@coachdave", displayName: "Dave",
                        avatarURL: nil, broCred: 9_300)
        let sam = User(id: UUID(), handle: "@newbro", displayName: "Sam",
                       avatarURL: nil, broCred: 40)
        return [
            Story(id: UUID(), author: marcus, caption: "Leg day 💀",
                  createdAt: .now.addingTimeInterval(-1_200), seen: false, accentIndex: 0),
            Story(id: UUID(), author: dave, caption: "Sunrise 10k done",
                  createdAt: .now.addingTimeInterval(-3_000), seen: false, accentIndex: 1),
            Story(id: UUID(), author: sam, caption: "First pull-up!",
                  createdAt: .now.addingTimeInterval(-5_400), seen: true, accentIndex: 2),
        ]
    }
}
