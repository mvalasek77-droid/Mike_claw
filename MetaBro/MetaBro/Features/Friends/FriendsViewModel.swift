import SwiftUI

/// Incoming requests, suggestions, and confirmed friends — all optimistic with
/// rollback, mirroring the vote/membership pattern used elsewhere.
@MainActor
@Observable
final class FriendsViewModel {
    enum State: Equatable {
        case loading
        case loaded(requests: [User], suggestions: [User], friends: [User])
        case error(String)
    }

    private(set) var state: State = .loading
    private let service: FriendsService

    init(service: FriendsService) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            async let requests = service.incomingRequests()
            async let suggestions = service.suggestions()
            async let friends = service.friends()
            let (r, s, f) = try await (requests, suggestions, friends)
            state = .loaded(requests: r, suggestions: s, friends: f)
        } catch {
            BroLog.error(error, category: "friends")
            state = .error("Couldn't load your Bros. Pull to refresh.")
        }
    }

    func sendRequest(to user: User) async {
        guard case .loaded(let requests, var suggestions, let friends) = state else { return }
        suggestions.removeAll { $0.id == user.id }
        state = .loaded(requests: requests, suggestions: suggestions, friends: friends)
        HapticsEngine.shared.play(.selectionChanged)
        do {
            try await service.sendRequest(to: user)
        } catch {
            BroLog.error(error, category: "friends")
            HapticsEngine.shared.play(.error)
            await load()
        }
    }

    func accept(_ user: User) async {
        guard case .loaded(var requests, let suggestions, var friends) = state else { return }
        requests.removeAll { $0.id == user.id }
        friends.append(user)
        state = .loaded(requests: requests, suggestions: suggestions, friends: friends)
        HapticsEngine.shared.play(.award)
        do {
            try await service.acceptRequest(from: user)
        } catch {
            BroLog.error(error, category: "friends")
            HapticsEngine.shared.play(.error)
            await load()
        }
    }

    func decline(_ user: User) async {
        guard case .loaded(var requests, let suggestions, let friends) = state else { return }
        requests.removeAll { $0.id == user.id }
        state = .loaded(requests: requests, suggestions: suggestions, friends: friends)
        HapticsEngine.shared.play(.selectionChanged)
        do {
            try await service.declineRequest(from: user)
        } catch {
            BroLog.error(error, category: "friends")
            HapticsEngine.shared.play(.error)
            await load()
        }
    }
}
