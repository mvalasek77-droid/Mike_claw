import Testing
import Foundation
@testable import MetaBro

@MainActor
struct FriendsViewModelTests {

    @Test func loadsRequestsSuggestionsAndFriends() async {
        let model = FriendsViewModel(service: MockFriendsService())
        await model.load()
        guard case .loaded(let requests, let suggestions, let friends) = model.state else {
            Issue.record("expected .loaded, got \(model.state)"); return
        }
        #expect(!requests.isEmpty)
        #expect(!suggestions.isEmpty)
        #expect(!friends.isEmpty)
    }

    @Test func acceptingARequestMovesUserFromRequestsToFriends() async {
        let model = FriendsViewModel(service: MockFriendsService())
        await model.load()
        guard case .loaded(let requests, _, let friendsBefore) = model.state,
              let incoming = requests.first else {
            Issue.record("need an incoming request"); return
        }
        await model.accept(incoming)

        guard case .loaded(let requestsAfter, _, let friendsAfter) = model.state else {
            Issue.record("expected .loaded after accept"); return
        }
        #expect(!requestsAfter.contains(incoming))
        #expect(friendsAfter.count == friendsBefore.count + 1)
        #expect(friendsAfter.contains(incoming))
    }

    @Test func decliningARequestRemovesItWithoutAddingAFriend() async {
        let model = FriendsViewModel(service: MockFriendsService())
        await model.load()
        guard case .loaded(let requests, _, let friendsBefore) = model.state,
              let incoming = requests.first else {
            Issue.record("need an incoming request"); return
        }
        await model.decline(incoming)

        guard case .loaded(let requestsAfter, _, let friendsAfter) = model.state else {
            Issue.record("expected .loaded after decline"); return
        }
        #expect(!requestsAfter.contains(incoming))
        #expect(friendsAfter.count == friendsBefore.count)
    }

    @Test func sendingARequestRemovesUserFromSuggestions() async {
        let model = FriendsViewModel(service: MockFriendsService())
        await model.load()
        guard case .loaded(_, let suggestionsBefore, _) = model.state,
              let candidate = suggestionsBefore.first else {
            Issue.record("need a suggestion"); return
        }
        await model.sendRequest(to: candidate)

        guard case .loaded(_, let suggestionsAfter, _) = model.state else {
            Issue.record("expected .loaded after sending a request"); return
        }
        #expect(!suggestionsAfter.contains(candidate))
    }
}

struct MockFriendsServiceTests {

    @Test func suggestionsExcludeFriendsAndPendingRequests() async throws {
        let service = MockFriendsService()
        let friends = try await service.friends()
        let incoming = try await service.incomingRequests()
        let outgoing = try await service.outgoingRequests()
        let suggestions = try await service.suggestions()

        for user in friends + incoming + outgoing {
            #expect(!suggestions.contains(user))
        }
    }

    @Test func acceptingMovesUserFromIncomingToFriends() async throws {
        let service = MockFriendsService()
        guard let incoming = try await service.incomingRequests().first else {
            Issue.record("need a seeded incoming request"); return
        }
        try await service.acceptRequest(from: incoming)
        let friends = try await service.friends()
        let remainingIncoming = try await service.incomingRequests()
        #expect(friends.contains(incoming))
        #expect(!remainingIncoming.contains(incoming))
    }

    @Test func unfriendRemovesFromFriendsList() async throws {
        let service = MockFriendsService()
        guard let friend = try await service.friends().first else {
            Issue.record("need a seeded friend"); return
        }
        try await service.unfriend(friend)
        let friends = try await service.friends()
        #expect(!friends.contains(friend))
    }
}

@MainActor
struct NotificationsViewModelTests {

    @Test func loadsNotifications() async {
        let model = NotificationsViewModel(service: MockNotificationsService())
        await model.load()
        guard case .loaded(let items) = model.state else {
            Issue.record("expected .loaded, got \(model.state)"); return
        }
        #expect(!items.isEmpty)
    }

    @Test func unreadCountReflectsOnlyUnreadItems() async {
        let model = NotificationsViewModel(service: MockNotificationsService())
        await model.load()
        guard case .loaded(let items) = model.state else {
            Issue.record("expected .loaded"); return
        }
        let expected = items.filter { !$0.isRead }.count
        #expect(model.unreadCount == expected)
        #expect(model.unreadCount > 0)
    }

    @Test func markingReadDecrementsUnreadCount() async {
        let model = NotificationsViewModel(service: MockNotificationsService())
        await model.load()
        guard case .loaded(let items) = model.state,
              let unread = items.first(where: { !$0.isRead }) else {
            Issue.record("need an unread notification"); return
        }
        let before = model.unreadCount
        await model.markRead(unread)
        #expect(model.unreadCount == before - 1)
    }

    @Test func markAllReadZerosTheUnreadCount() async {
        let model = NotificationsViewModel(service: MockNotificationsService())
        await model.load()
        await model.markAllRead()
        #expect(model.unreadCount == 0)
    }

    @Test func emptyServiceProducesEmptyState() async {
        let model = NotificationsViewModel(service: MockNotificationsService(items: []))
        await model.load()
        #expect(model.state == .empty)
    }
}

struct MockNotificationsServiceTests {

    @Test func notificationsAreSortedNewestFirst() async throws {
        let service = MockNotificationsService()
        let items = try await service.notifications()
        #expect(items == items.sorted { $0.createdAt > $1.createdAt })
    }

    @Test func markReadFlipsOnlyTheTargetedItem() async throws {
        let service = MockNotificationsService()
        guard let target = try await service.notifications().first(where: { !$0.isRead }) else {
            Issue.record("need an unread seeded notification"); return
        }
        try await service.markRead(target.id)
        let after = try await service.notifications()
        #expect(after.first { $0.id == target.id }?.isRead == true)
    }

    @Test func markAllReadFlipsEveryItem() async throws {
        let service = MockNotificationsService()
        try await service.markAllRead()
        let after = try await service.notifications()
        #expect(after.allSatisfy { $0.isRead })
    }
}
