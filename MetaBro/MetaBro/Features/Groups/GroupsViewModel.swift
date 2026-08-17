import SwiftUI

/// Drives the groups list: every private friend group the current user belongs to.
@MainActor
@Observable
final class GroupsViewModel {
    enum State: Equatable {
        case loading
        case loaded([FriendGroup])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading
    private let service: GroupService

    init(service: GroupService) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            let groups = try await service.myGroups()
            state = groups.isEmpty ? .empty : .loaded(groups)
        } catch {
            BroLog.error(error, category: "groups")
            state = .error("Couldn't load your groups.")
        }
    }

    /// Inserts a freshly-created group at the front of the loaded list.
    func created(_ group: FriendGroup) {
        guard case .loaded(var groups) = state else {
            state = .loaded([group])
            return
        }
        groups.insert(group, at: 0)
        state = .loaded(groups)
    }
}
