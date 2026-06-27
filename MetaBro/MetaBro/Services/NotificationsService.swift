import Foundation

/// Granular, actionable activity feed: friend requests, reactions, votes,
/// comments, awards, mentions. Read state is per-item so the bell badge
/// reflects exactly what's unread.
protocol NotificationsService: Sendable {
    func notifications() async throws -> [AppNotification]
    func markRead(_ id: UUID) async throws
    func markAllRead() async throws
}

/// Deterministic in-memory notifications for previews, tests, and offline demo.
actor MockNotificationsService: NotificationsService {
    private var items: [AppNotification]

    init(items: [AppNotification] = MockNotificationsService.seed()) {
        self.items = items
    }

    func notifications() async throws -> [AppNotification] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    func markRead(_ id: UUID) async throws {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isRead = true
    }

    func markAllRead() async throws {
        for i in items.indices { items[i].isRead = true }
    }

    static func seed() -> [AppNotification] {
        let marcus = User(id: UUID(), handle: "@ironbro", displayName: "Marcus", avatarURL: nil, broCred: 4_820)
        let dave = User(id: UUID(), handle: "@coachdave", displayName: "Dave", avatarURL: nil, broCred: 9_300)
        let sam = User(id: UUID(), handle: "@newbro", displayName: "Sam", avatarURL: nil, broCred: 40)
        return [
            AppNotification(id: UUID(), kind: .friendRequest, actor: sam,
                             message: "Sam sent you a Bro request", post: nil,
                             createdAt: .now.addingTimeInterval(-900), isRead: false),
            AppNotification(id: UUID(), kind: .reaction, actor: marcus,
                             message: "Marcus respected your post", post: nil,
                             createdAt: .now.addingTimeInterval(-3_600), isRead: false),
            AppNotification(id: UUID(), kind: .comment, actor: dave,
                             message: "Dave commented on your post", post: nil,
                             createdAt: .now.addingTimeInterval(-7_200), isRead: true),
        ]
    }
}
