import Foundation

protocol CommunityService: Sendable {
    func discover() async throws -> [Community]
    func setMembership(communityID: UUID, joined: Bool) async throws
}

/// Deterministic in-memory Bro-hoods for previews, tests, and offline demo.
actor MockCommunityService: CommunityService {
    private var communities: [Community]

    init(communities: [Community] = MockCommunityService.seed()) {
        self.communities = communities
    }

    func discover() async throws -> [Community] {
        try await Task.sleep(nanoseconds: 200_000_000)
        return communities.sorted { $0.memberCount > $1.memberCount }
    }

    func setMembership(communityID: UUID, joined: Bool) async throws {
        guard let idx = communities.firstIndex(where: { $0.id == communityID }) else { return }
        communities[idx].isJoined = joined
        communities[idx].memberCount += joined ? 1 : -1
    }

    static func seed() -> [Community] {
        [
            Community(id: UUID(), name: "Iron Bro-hood", slug: "fitness",
                      memberCount: 182_000, iconURL: nil, isJoined: true, isModerator: true),
            Community(id: UUID(), name: "Grill Masters", slug: "bbq",
                      memberCount: 96_400, iconURL: nil, isJoined: false),
            Community(id: UUID(), name: "Garage Gearheads", slug: "cars",
                      memberCount: 141_200, iconURL: nil, isJoined: false),
            Community(id: UUID(), name: "Dad Mode", slug: "fatherhood",
                      memberCount: 58_700, iconURL: nil, isJoined: true),
            Community(id: UUID(), name: "Stoic Bros", slug: "philosophy",
                      memberCount: 22_300, iconURL: nil, isJoined: false),
            Community(id: UUID(), name: "Heavy Recovery", slug: "injuries",
                      memberCount: 8_900, iconURL: nil, isJoined: false, isMature: true),
        ]
    }
}
