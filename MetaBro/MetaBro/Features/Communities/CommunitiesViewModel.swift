import SwiftUI

/// Discover + join/leave Bro-hoods. Membership toggles are optimistic and roll
/// back on failure, mirroring the feed/comment voting pattern.
@MainActor
@Observable
final class CommunitiesViewModel {
    enum State: Equatable {
        case loading
        case loaded([Community])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading
    private let service: CommunityService

    init(service: CommunityService) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            let communities = try await service.discover()
            state = communities.isEmpty ? .empty : .loaded(communities)
        } catch {
            state = .error("Couldn't load Bro-hoods. Pull to refresh.")
        }
    }

    func toggleMembership(_ community: Community) async {
        guard case .loaded(var communities) = state,
              let idx = communities.firstIndex(where: { $0.id == community.id }) else { return }

        let previous = communities[idx]
        let joining = !previous.isJoined
        communities[idx].isJoined = joining
        communities[idx].memberCount += joining ? 1 : -1
        state = .loaded(communities)
        HapticsEngine.shared.play(joining ? .award : .selectionChanged)

        do {
            try await service.setMembership(communityID: community.id, joined: joining)
        } catch {
            if case .loaded(var current) = state,
               let i = current.firstIndex(where: { $0.id == community.id }) {
                current[i] = previous
                state = .loaded(current)
            }
            HapticsEngine.shared.play(.error)
        }
    }
}
