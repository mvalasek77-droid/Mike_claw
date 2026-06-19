import Testing
import Foundation
@testable import MetaBro

@MainActor
struct CommunitiesViewModelTests {

    @Test func loadsCommunities() async {
        let model = CommunitiesViewModel(service: MockCommunityService())
        await model.load()
        guard case .loaded(let communities) = model.state else {
            Issue.record("expected .loaded, got \(model.state)"); return
        }
        #expect(!communities.isEmpty)
        // Discover sorts by member count, descending.
        #expect(communities == communities.sorted { $0.memberCount > $1.memberCount })
    }

    @Test func joiningTogglesMembershipAndCount() async {
        let model = CommunitiesViewModel(service: MockCommunityService())
        await model.load()
        guard case .loaded(let communities) = model.state,
              let notJoined = communities.first(where: { !$0.isJoined }) else {
            Issue.record("need a not-joined community"); return
        }
        await model.toggleMembership(notJoined)

        guard case .loaded(let after) = model.state,
              let updated = after.first(where: { $0.id == notJoined.id }) else {
            Issue.record("community vanished"); return
        }
        #expect(updated.isJoined)
        #expect(updated.memberCount == notJoined.memberCount + 1)
    }

    @Test func emptyServiceProducesEmptyState() async {
        let model = CommunitiesViewModel(service: MockCommunityService(communities: []))
        await model.load()
        #expect(model.state == .empty)
    }
}
