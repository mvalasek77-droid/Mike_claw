import Testing
import Foundation
@testable import MetaBro

/// Coverage for this slice: mod queue triage, pin/lock with rollback, pinned
/// posts sorting first in the feed, the 1:1-only chat safety target, and the
/// `User`/`Community` decode-default fix that caused the CI regression.
@MainActor
struct ModQueueViewModelTests {

    @Test func loadsPendingReports() async {
        let model = ModQueueViewModel(service: MockModerationService())
        await model.load()
        guard case .loaded(let reports) = model.state else {
            Issue.record("expected .loaded, got \(model.state)"); return
        }
        #expect(reports.allSatisfy { $0.status == .pending })
    }

    @Test func emptyQueueProducesEmptyState() async {
        let model = ModQueueViewModel(service: MockModerationService(reports: []))
        await model.load()
        #expect(model.state == .empty)
    }

    @Test func approveRemovesReportFromQueue() async {
        let model = ModQueueViewModel(service: MockModerationService())
        await model.load()
        guard case .loaded(let before) = model.state, let first = before.first else {
            Issue.record("no reports"); return
        }
        await model.approve(first)

        guard case .loaded(let after) = model.state else {
            if case .empty = model.state { return }
            Issue.record("expected .loaded or .empty, got \(model.state)"); return
        }
        #expect(!after.contains { $0.id == first.id })
    }

    @Test func removeDropsReportFromQueue() async {
        let model = ModQueueViewModel(service: MockModerationService())
        await model.load()
        guard case .loaded(let before) = model.state, let first = before.first else {
            Issue.record("no reports"); return
        }
        await model.remove(first)

        guard case .loaded(let after) = model.state else {
            if case .empty = model.state { return }
            Issue.record("expected .loaded or .empty, got \(model.state)"); return
        }
        #expect(!after.contains { $0.id == first.id })
    }

    @Test func banRemovesReportAndBansUser() async {
        let service = MockModerationService()
        let model = ModQueueViewModel(service: service)
        await model.load()
        guard case .loaded(let before) = model.state, let first = before.first else {
            Issue.record("no reports"); return
        }
        await model.ban(first)

        guard case .loaded(let after) = model.state else {
            if case .empty = model.state { return }
            Issue.record("expected .loaded or .empty, got \(model.state)"); return
        }
        #expect(!after.contains { $0.id == first.id })
        let banned = await service.bannedUsers
        #expect(banned.contains(first.reportedUser.id))
    }
}

@MainActor
struct PostDetailModerationTests {

    private func makeModeratedPost() -> Post {
        let community = Community(id: UUID(), name: "Iron Bro-hood", slug: "fitness",
                                   memberCount: 1, iconURL: nil, isJoined: true, isModerator: true)
        let author = User(id: UUID(), handle: "@op", displayName: "OP", avatarURL: nil, broCred: 1)
        return Post(id: UUID(), author: author, community: community, title: "Test", body: "Body",
                    imageURL: nil, score: 1, commentCount: 0, createdAt: .now, myVote: .none)
    }

    @Test func togglePinFlipsStateOptimistically() async {
        let post = makeModeratedPost()
        let model = PostDetailViewModel(post: post, service: MockCommentService(),
                                         moderationService: MockModerationService())
        #expect(model.canModerate)
        #expect(!model.post.isPinned)
        await model.togglePin()
        #expect(model.post.isPinned)
        await model.togglePin()
        #expect(!model.post.isPinned)
    }

    @Test func toggleLockRollsBackOnFailure() async {
        let post = makeModeratedPost()
        let model = PostDetailViewModel(post: post, service: MockCommentService(),
                                         moderationService: FailingModerationService())
        #expect(!model.post.isLocked)
        await model.toggleLock()
        #expect(!model.post.isLocked)
    }
}

@MainActor
struct FeedPinnedOrderingTests {

    @Test func pinnedPostsLoadFirst() async {
        let author = User(id: UUID(), handle: "@a", displayName: "A", avatarURL: nil, broCred: 1)
        var pinned = Post(id: UUID(), author: author, community: nil, title: nil, body: "pinned",
                           imageURL: nil, score: 1, commentCount: 0, createdAt: .now, myVote: .none)
        pinned.isPinned = true
        let unpinned = Post(id: UUID(), author: author, community: nil, title: nil, body: "regular",
                             imageURL: nil, score: 1, commentCount: 0, createdAt: .now, myVote: .none)

        let service = OrderedFeedService(posts: [unpinned, pinned])
        let model = FeedViewModel(service: service)
        await model.load()

        guard case .loaded(let posts) = model.state else {
            Issue.record("expected .loaded, got \(model.state)"); return
        }
        #expect(posts.first?.isPinned == true)
    }
}

@MainActor
struct ChatPartnerTests {

    @Test func partnerIsNilForGroupChats() {
        let participant = User(id: UUID(), handle: "@a", displayName: "A", avatarURL: nil, broCred: 1)
        let convo = Conversation(id: UUID(), participants: [participant], isGroup: true,
                                  title: "Squad", lastMessage: "", lastActivity: .now, unreadCount: 0)
        let model = ChatViewModel(conversation: convo, service: MockMessagingService())
        #expect(model.partner == nil)
    }

    @Test func partnerIsTheOtherParticipantForOneOnOne() {
        let participant = User(id: UUID(), handle: "@a", displayName: "A", avatarURL: nil, broCred: 1)
        let convo = Conversation(id: UUID(), participants: [participant], isGroup: false,
                                  title: nil, lastMessage: "", lastActivity: .now, unreadCount: 0)
        let model = ChatViewModel(conversation: convo, service: MockMessagingService())
        #expect(model.partner?.id == participant.id)
    }
}

struct DecodeDefaultsTests {

    @Test func userDecodesWithoutPresenceKeys() throws {
        let json = """
        {"id":"\(UUID().uuidString)","handle":"@bro","displayName":"Bro","broCred":10}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let user = try decoder.decode(User.self, from: json)
        #expect(user.isOnline == false)
        #expect(user.lastActiveAt == nil)
    }

    @Test func communityDecodesWithoutModeratorOrMatureKeys() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Iron Bro-hood","slug":"fitness",
         "memberCount":5,"isJoined":true}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let community = try decoder.decode(Community.self, from: json)
        #expect(community.isModerator == false)
        #expect(community.isMature == false)
    }
}

// MARK: - Test doubles

private struct FailingModerationService: ModerationService {
    func queue() async throws -> [Report] { [] }
    func approve(_ report: Report) async throws {}
    func remove(_ report: Report) async throws {}
    func pin(postID: UUID) async throws { throw APIError.server(status: 500) }
    func unpin(postID: UUID) async throws { throw APIError.server(status: 500) }
    func lock(postID: UUID) async throws { throw APIError.server(status: 500) }
    func unlock(postID: UUID) async throws { throw APIError.server(status: 500) }
    func ban(_ user: User, from community: Community) async throws {}
}

private struct OrderedFeedService: FeedService {
    let posts: [Post]
    func feed(sort: FeedSort, cursor: String?) async throws -> FeedPage {
        FeedPage(posts: posts, nextCursor: nil)
    }
    func vote(postID: UUID, value: VoteValue) async throws {}
    func react(postID: UUID, reaction: ReactionKind?) async throws {}
    func giveAward(postID: UUID, award: AwardKind) async throws {}
    func createPost(_ draft: PostDraft) async throws -> Post { throw APIError.offline }
    func posts(by userID: UUID) async throws -> [Post] { [] }
}
