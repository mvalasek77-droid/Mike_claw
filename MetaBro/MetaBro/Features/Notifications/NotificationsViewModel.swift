import SwiftUI

/// Drives the activity bell: unread count for the badge, and per-item or
/// mark-all-read actions. Held by `FeedView` (not constructed by the
/// notifications screen itself) so the badge updates live as items are read.
@MainActor
@Observable
final class NotificationsViewModel {
    enum State: Equatable {
        case loading
        case loaded([AppNotification])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading
    private let service: NotificationsService

    init(service: NotificationsService) {
        self.service = service
    }

    var unreadCount: Int {
        guard case .loaded(let items) = state else { return 0 }
        return items.filter { !$0.isRead }.count
    }

    func load() async {
        state = .loading
        do {
            let items = try await service.notifications()
            state = items.isEmpty ? .empty : .loaded(items)
        } catch {
            BroLog.error(error, category: "notifications")
            state = .error("Couldn't load notifications. Pull to refresh.")
        }
    }

    func markRead(_ notification: AppNotification) async {
        guard case .loaded(var items) = state,
              let idx = items.firstIndex(where: { $0.id == notification.id }),
              !items[idx].isRead else { return }
        items[idx].isRead = true
        state = .loaded(items)
        do {
            try await service.markRead(notification.id)
        } catch {
            BroLog.error(error, category: "notifications")
        }
    }

    func markAllRead() async {
        guard case .loaded(var items) = state, items.contains(where: { !$0.isRead }) else { return }
        for i in items.indices { items[i].isRead = true }
        state = .loaded(items)
        do {
            try await service.markAllRead()
        } catch {
            BroLog.error(error, category: "notifications")
        }
    }
}
