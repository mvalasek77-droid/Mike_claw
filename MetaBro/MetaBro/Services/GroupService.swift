import Foundation

protocol GroupService: Sendable {
    /// Groups the current user belongs to.
    func myGroups() async throws -> [FriendGroup]
    /// Creates a group (the current user + the given members) and returns it.
    func create(_ draft: GroupDraft) async throws -> FriendGroup
    /// A group's posts, newest first.
    func posts(in groupID: UUID) async throws -> [GroupPost]
    /// Creates a post authored by the current user in the group's feed.
    func createPost(in groupID: UUID, body: String) async throws -> GroupPost
    func setLiked(groupID: UUID, postID: UUID, liked: Bool) async throws
}

/// Deterministic in-memory groups for previews, tests, and offline demo.
actor MockGroupService: GroupService {
    private var groups: [FriendGroup]
    private var postsByGroup: [UUID: [GroupPost]]

    init(groups: [FriendGroup]? = nil, postsByGroup: [UUID: [GroupPost]]? = nil) {
        if let groups, let postsByGroup {
            self.groups = groups
            self.postsByGroup = postsByGroup
        } else {
            let seed = MockGroupService.seed()
            self.groups = groups ?? seed.groups
            self.postsByGroup = postsByGroup ?? seed.posts
        }
    }

    func myGroups() async throws -> [FriendGroup] {
        try await Task.sleep(nanoseconds: 200_000_000)
        return groups.sorted { $0.name < $1.name }
    }

    func create(_ draft: GroupDraft) async throws -> FriendGroup {
        guard draft.isValid else { throw APIError.server(status: 422) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let group = FriendGroup(id: UUID(), name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                           description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                           members: [Session.me] + draft.members, createdBy: Session.me)
        groups.insert(group, at: 0)
        postsByGroup[group.id] = []
        return group
    }

    func posts(in groupID: UUID) async throws -> [GroupPost] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return (postsByGroup[groupID] ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    func createPost(in groupID: UUID, body: String) async throws -> GroupPost {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.server(status: 422) }
        try await Task.sleep(nanoseconds: 150_000_000)
        let post = GroupPost(id: UUID(), author: Session.me, body: trimmed,
                              createdAt: .now, likeCount: 0, likedByMe: false)
        postsByGroup[groupID, default: []].insert(post, at: 0)
        return post
    }

    func setLiked(groupID: UUID, postID: UUID, liked: Bool) async throws {
        guard var posts = postsByGroup[groupID],
              let idx = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard posts[idx].likedByMe != liked else { return }
        posts[idx].likedByMe = liked
        posts[idx].likeCount += liked ? 1 : -1
        postsByGroup[groupID] = posts
    }

    static func seed() -> (groups: [FriendGroup], posts: [UUID: [GroupPost]]) {
        let dave = User(id: UUID(), handle: "@coachdave", displayName: "Dave", avatarURL: nil, broCred: 9_300)
        let marcus = User(id: UUID(), handle: "@ironbro", displayName: "Marcus", avatarURL: nil, broCred: 4_820)
        let raj = User(id: UUID(), handle: "@rajlifts", displayName: "Raj", avatarURL: nil, broCred: 3_050)

        let lifting = FriendGroup(id: UUID(), name: "Saturday Lift Crew",
                             description: "Just the squad — meetup planning and PR talk.",
                             members: [Session.me, dave, marcus], createdBy: Session.me)
        let poker = FriendGroup(id: UUID(), name: "Thursday Poker Night",
                           description: "Buy-in's $20, loser brings snacks next time.",
                           members: [Session.me, marcus, raj], createdBy: marcus)

        let liftingPosts = [
            GroupPost(id: UUID(), author: dave, body: "Squat rack's free Saturday 9am, who's in?",
                      createdAt: .now.addingTimeInterval(-3_600), likeCount: 2, likedByMe: true),
            GroupPost(id: UUID(), author: marcus, body: "In. Bringing the good chalk this time.",
                      createdAt: .now.addingTimeInterval(-7_200), likeCount: 1, likedByMe: false)
        ]
        let pokerPosts = [
            GroupPost(id: UUID(), author: raj, body: "New deck this week, mine got bent to hell.",
                      createdAt: .now.addingTimeInterval(-1_800), likeCount: 0, likedByMe: false)
        ]

        return (groups: [lifting, poker],
                posts: [lifting.id: liftingPosts, poker.id: pokerPosts])
    }
}
