import Testing
import Foundation
@testable import MetaBro

/// Coverage for this slice: private group creation (current user + invited
/// friends), a group's own post feed, optimistic like with rollback, and the
/// groups list/detail view models.
@MainActor
struct MockGroupServiceTests {

    @Test func createInsertsGroupWithCurrentUserAsMember() async throws {
        let service = MockGroupService(groups: [], postsByGroup: [:])
        let friend = User(id: UUID(), handle: "@bro", displayName: "Bro", avatarURL: nil, broCred: 0)
        let draft = GroupDraft(name: "Late Night Crew", description: "", members: [friend])

        let group = try await service.create(draft)
        #expect(group.members.contains { $0.id == Session.me.id })
        #expect(group.members.contains { $0.id == friend.id })

        let all = try await service.myGroups()
        #expect(all.contains { $0.id == group.id })
    }

    @Test func createRejectsDraftWithNoMembers() async {
        let service = MockGroupService(groups: [], postsByGroup: [:])
        let draft = GroupDraft(name: "Empty Crew", description: "", members: [])
        await #expect(throws: APIError.self) {
            _ = try await service.create(draft)
        }
    }

    @Test func createPostInsertsAtFrontOfGroupFeed() async throws {
        let service = MockGroupService()
        let group = try #require(try await service.myGroups().first)

        let post = try await service.createPost(in: group.id, body: "Who's free Friday?")
        let posts = try await service.posts(in: group.id)
        #expect(posts.first?.id == post.id)
        #expect(post.author.id == Session.me.id)
    }

    @Test func createPostRejectsEmptyBody() async throws {
        let service = MockGroupService()
        let group = try #require(try await service.myGroups().first)
        await #expect(throws: APIError.self) {
            _ = try await service.createPost(in: group.id, body: "   ")
        }
    }

    @Test func setLikedTogglesLikeCount() async throws {
        let service = MockGroupService()
        let group = try #require(try await service.myGroups().first)
        let post = try #require(try await service.posts(in: group.id).first)
        let beforeCount = post.likeCount
        let wasLiked = post.likedByMe

        try await service.setLiked(groupID: group.id, postID: post.id, liked: !wasLiked)
        let after = try #require(try await service.posts(in: group.id).first { $0.id == post.id })
        #expect(after.likedByMe == !wasLiked)
        #expect(after.likeCount == beforeCount + (wasLiked ? -1 : 1))
    }
}

@MainActor
struct GroupsViewModelTests {

    @Test func loadPopulatesGroups() async {
        let model = GroupsViewModel(service: MockGroupService())
        await model.load()
        guard case .loaded = model.state else {
            Issue.record("expected .loaded, got \(model.state)"); return
        }
    }

    @Test func emptyServiceProducesEmptyState() async {
        let model = GroupsViewModel(service: MockGroupService(groups: [], postsByGroup: [:]))
        await model.load()
        #expect(model.state == .empty)
    }

    @Test func createdInsertsAtFront() async {
        let model = GroupsViewModel(service: MockGroupService())
        await model.load()
        let fresh = FriendGroup(id: UUID(), name: "Brand New Crew", description: "",
                                 members: [Session.me], createdBy: Session.me)
        model.created(fresh)

        guard case .loaded(let groups) = model.state else {
            Issue.record("expected .loaded"); return
        }
        #expect(groups.first?.id == fresh.id)
    }
}

@MainActor
struct GroupDetailViewModelTests {

    @Test func postAppendsToLoadedFeed() async throws {
        let service = MockGroupService()
        let group = try #require(try await service.myGroups().first)
        let model = GroupDetailViewModel(group: group, service: service)
        await model.load()

        model.draft = "Bringing the cooler this time."
        await model.post()

        guard case .loaded(let posts) = model.state else {
            Issue.record("expected .loaded"); return
        }
        #expect(posts.first?.body == "Bringing the cooler this time.")
        #expect(model.draft.isEmpty)
    }

    @Test func toggleLikeRollsBackOnFailure() async throws {
        let group = FriendGroup(id: UUID(), name: "Test Crew", description: "",
                                 members: [Session.me], createdBy: Session.me)
        let post = GroupPost(id: UUID(), author: Session.me, body: "hey", createdAt: .now,
                              likeCount: 0, likedByMe: false)
        let model = GroupDetailViewModel(group: group, service: FailingGroupService(seedPost: post))
        await model.load()

        await model.toggleLike(post)

        guard case .loaded(let posts) = model.state,
              let updated = posts.first(where: { $0.id == post.id }) else {
            Issue.record("post vanished"); return
        }
        #expect(updated.likedByMe == false) // rolled back
        #expect(updated.likeCount == 0)
    }
}

private struct FailingGroupService: GroupService {
    let seedPost: GroupPost

    func myGroups() async throws -> [FriendGroup] { [] }
    func create(_ draft: GroupDraft) async throws -> FriendGroup {
        throw APIError.server(status: 500)
    }
    func posts(in groupID: UUID) async throws -> [GroupPost] { [seedPost] }
    func createPost(in groupID: UUID, body: String) async throws -> GroupPost {
        throw APIError.server(status: 500)
    }
    func setLiked(groupID: UUID, postID: UUID, liked: Bool) async throws {
        throw APIError.server(status: 500)
    }
}
