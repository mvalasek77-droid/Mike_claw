import Foundation

/// Facebook-style friend graph, distinct from Bro-hood membership: requests are
/// one-sided until accepted, at which point both sides see each other in
/// `friends()`. Drives the social half of the feed fusion.
protocol FriendsService: Sendable {
    func friends() async throws -> [User]
    /// Requests other people have sent you, awaiting your response.
    func incomingRequests() async throws -> [User]
    /// Requests you've sent that haven't been accepted yet.
    func outgoingRequests() async throws -> [User]
    /// People you're not yet connected to, worth suggesting.
    func suggestions() async throws -> [User]
    func sendRequest(to user: User) async throws
    func acceptRequest(from user: User) async throws
    func declineRequest(from user: User) async throws
    func unfriend(_ user: User) async throws
}

/// Deterministic in-memory friend graph for previews, tests, and offline demo.
actor MockFriendsService: FriendsService {
    private var friendsList: [User]
    private var incoming: [User]
    private var outgoing: [User]
    private var suggested: [User]

    init() {
        let seed = MockFriendsService.seed()
        self.friendsList = seed.friends
        self.incoming = seed.incoming
        self.outgoing = seed.outgoing
        self.suggested = seed.suggestions
    }

    func friends() async throws -> [User] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return friendsList.sorted { $0.displayName < $1.displayName }
    }

    func incomingRequests() async throws -> [User] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return incoming
    }

    func outgoingRequests() async throws -> [User] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return outgoing
    }

    func suggestions() async throws -> [User] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return suggested.filter {
            !friendsList.contains($0) && !incoming.contains($0) && !outgoing.contains($0)
        }
    }

    func sendRequest(to user: User) async throws {
        guard !outgoing.contains(user), !friendsList.contains(user) else { return }
        outgoing.append(user)
    }

    func acceptRequest(from user: User) async throws {
        guard let idx = incoming.firstIndex(of: user) else { return }
        incoming.remove(at: idx)
        friendsList.append(user)
    }

    func declineRequest(from user: User) async throws {
        incoming.removeAll { $0 == user }
    }

    func unfriend(_ user: User) async throws {
        friendsList.removeAll { $0 == user }
    }

    static func seed() -> (friends: [User], incoming: [User], outgoing: [User], suggestions: [User]) {
        let marcus = User(id: UUID(), handle: "@ironbro", displayName: "Marcus", avatarURL: nil, broCred: 4_820)
        let dave = User(id: UUID(), handle: "@coachdave", displayName: "Dave", avatarURL: nil, broCred: 9_300)
        let sam = User(id: UUID(), handle: "@newbro", displayName: "Sam", avatarURL: nil, broCred: 40)
        let theo = User(id: UUID(), handle: "@theoknows", displayName: "Theo", avatarURL: nil, broCred: 1_120)
        let raj = User(id: UUID(), handle: "@rajlifts", displayName: "Raj", avatarURL: nil, broCred: 3_050)
        let leo = User(id: UUID(), handle: "@leobuilds", displayName: "Leo", avatarURL: nil, broCred: 760)

        return (
            friends: [marcus, dave],
            incoming: [sam],
            outgoing: [theo],
            suggestions: [raj, leo]
        )
    }
}
