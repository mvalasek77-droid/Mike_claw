import Testing
import Foundation
@testable import MetaBro

/// In-memory APIClient for testing live services without a network. Returns
/// canned JSON for reads and records mutation calls for assertions.
final class FakeAPIClient: APIClient, @unchecked Sendable {
    var responses: [String: Data] = [:]
    private(set) var mutations: [String] = []

    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        guard let data = responses[endpoint.path] else { throw APIError.server(status: 404) }
        do { return try JSON.decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding }
    }

    func send(_ endpoint: Endpoint) async throws {
        mutations.append("\(endpoint.method.rawValue) \(endpoint.path)")
    }
}

@MainActor
struct LiveBackendTests {

    private let postID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let authorID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func postJSON() -> String {
        """
        {
          "id": "\(postID.uuidString)",
          "author": { "id": "\(authorID.uuidString)", "handle": "@ironbro",
                      "display_name": "Marcus", "avatar_url": null, "bro_cred": 4820 },
          "community": null,
          "title": "Warm up",
          "body": "Bands before barbell",
          "image_url": null,
          "score": 10,
          "comment_count": 3,
          "created_at": "2026-06-20T10:00:00Z",
          "my_vote": 1,
          "reactions": [ {"kind":"strong","count":14}, {"kind":"respect","count":9} ],
          "my_reaction": "strong",
          "awards": [ {"kind":"champ","count":1} ]
        }
        """
    }

    // MARK: DTO mapping

    @Test func postDTOMapsReactionsVotesAndAwards() throws {
        let dto = try JSON.decoder.decode(PostDTO.self, from: Data(postJSON().utf8))
        let post = dto.toDomain()
        #expect(post.id == postID)
        #expect(post.origin == .social)              // community null
        #expect(post.myVote == .up)
        #expect(post.reactions.mine == .strong)
        #expect(post.reactions.counts[.strong] == 14)
        #expect(post.reactions.total == 23)
        #expect(post.awards[.champ] == 1)
    }

    @Test func feedServiceDecodesPage() async throws {
        let client = FakeAPIClient()
        client.responses["feed"] = Data("""
        { "posts": [ \(postJSON()) ], "next_cursor": "abc" }
        """.utf8)
        let service = LiveFeedService(client: client)
        let page = try await service.feed(sort: .hot, cursor: nil)
        #expect(page.posts.count == 1)
        #expect(page.nextCursor == "abc")
        #expect(page.posts.first?.reactions.mine == .strong)
    }

    // MARK: Mutations hit the right routes

    @Test func voteHitsExpectedEndpoint() async throws {
        let client = FakeAPIClient()
        let service = LiveFeedService(client: client)
        try await service.vote(postID: postID, value: .up)
        #expect(client.mutations == ["POST posts/\(postID.uuidString)/vote"])
    }

    @Test func giveAwardHitsExpectedEndpoint() async throws {
        let client = FakeAPIClient()
        let service = LiveFeedService(client: client)
        try await service.giveAward(postID: postID, award: .champ)
        #expect(client.mutations == ["POST posts/\(postID.uuidString)/awards"])
    }

    @Test func joinAndLeaveUseDifferentMethods() async throws {
        let client = FakeAPIClient()
        let service = LiveCommunityService(client: client)
        let id = UUID()
        try await service.setMembership(communityID: id, joined: true)
        try await service.setMembership(communityID: id, joined: false)
        #expect(client.mutations == [
            "POST communities/\(id.uuidString)/membership",
            "DELETE communities/\(id.uuidString)/membership",
        ])
    }

    @Test func sendingAVoiceNoteHitsTheMessagesEndpoint() async throws {
        let client = FakeAPIClient()
        let service = LiveMessagingService(client: client)
        let conversationID = UUID()
        let sender = User(id: UUID(), handle: "@ironbro", displayName: "Marcus", avatarURL: nil, broCred: 4_820)
        let voiceNote = Message(id: UUID(), conversationID: conversationID, sender: sender,
                                 text: "Voice note", sentAt: .now, status: .sending, voiceNoteDuration: 8)
        try await service.send(voiceNote, to: conversationID)
        #expect(client.mutations == ["POST conversations/\(conversationID.uuidString)/messages"])
    }

    @Test func registeringADeviceTokenHitsExpectedEndpoint() async throws {
        let client = FakeAPIClient()
        let service = LivePushNotificationService(client: client)
        try await service.registerDeviceToken("abc123")
        #expect(client.mutations == ["POST push/device-tokens"])
    }

    // MARK: Config

    @Test func liveModeRequiresFlagAndURL() {
        let url = URL(string: "https://api.metabro.app/v1")!
        #expect(BackendConfig(baseURL: url, useLive: true).resolvedBaseURL == url)
        #expect(BackendConfig(baseURL: url, useLive: false).resolvedBaseURL == nil)
        #expect(BackendConfig(baseURL: nil, useLive: true).resolvedBaseURL == nil)
    }

    @Test func containerFallsBackToMocksWithoutConfig() {
        // No base URL → mock graph; the app still works fully offline.
        let container = AppContainer.resolve(config: BackendConfig(baseURL: nil, useLive: false))
        #expect(container.feedService is MockFeedService)
    }

    @Test func containerUsesLiveServicesWhenConfigured() {
        let url = URL(string: "https://api.metabro.app/v1")!
        let container = AppContainer.resolve(config: BackendConfig(baseURL: url, useLive: true))
        #expect(container.feedService is LiveFeedService)
        #expect(container.messagingService is LiveMessagingService)
        #expect(container.bugReportService is LiveBugReportService)
        #expect(container.friendsService is LiveFriendsService)
        #expect(container.notificationsService is LiveNotificationsService)
        #expect(container.pushNotificationService is LivePushNotificationService)
    }

    // MARK: Bug reports

    @Test func bugReportSubmissionHitsExpectedEndpoint() async throws {
        let client = FakeAPIClient()
        let service = LiveBugReportService(client: client)
        let draft = BugReportDraft(summary: "Crash on post", details: "Tapping vote crashes the app",
                                    severity: .crash, includeDiagnostics: false)
        try await service.submit(draft)
        #expect(client.mutations == ["POST bug-reports"])
    }

    // MARK: Friends & notifications

    @Test func sendAcceptDeclineAndUnfriendHitExpectedEndpoints() async throws {
        let client = FakeAPIClient()
        let service = LiveFriendsService(client: client)
        let user = User(id: UUID(), handle: "@bro", displayName: "Bro", avatarURL: nil, broCred: 0)
        try await service.sendRequest(to: user)
        try await service.acceptRequest(from: user)
        try await service.declineRequest(from: user)
        try await service.unfriend(user)
        #expect(client.mutations == [
            "POST friends/requests/\(user.id.uuidString)",
            "POST friends/requests/\(user.id.uuidString)/respond",
            "POST friends/requests/\(user.id.uuidString)/respond",
            "DELETE friends/\(user.id.uuidString)",
        ])
    }

    @Test func markNotificationReadAndMarkAllReadHitExpectedEndpoints() async throws {
        let client = FakeAPIClient()
        let service = LiveNotificationsService(client: client)
        let id = UUID()
        try await service.markRead(id)
        try await service.markAllRead()
        #expect(client.mutations == [
            "POST notifications/\(id.uuidString)/read",
            "POST notifications/read-all",
        ])
    }
}
