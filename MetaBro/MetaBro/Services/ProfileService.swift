import Foundation

protocol ProfileService: Sendable {
    /// Builds the signed-in user's profile (identity, karma, memberships, posts).
    func myProfile() async throws -> Profile
}

/// Composes the profile from the live feed + community services so it reflects
/// posts you've just created and Bro-hoods you've just joined — no separate
/// source of truth to drift out of sync.
struct MockProfileService: ProfileService {
    let feedService: FeedService
    let communityService: CommunityService

    func myProfile() async throws -> Profile {
        async let myPosts = feedService.posts(by: Session.me.id)
        async let communities = communityService.discover()

        let posts = try await myPosts
        let joined = try await communities.filter(\.isJoined)

        // Post karma derives from authored posts; comment karma is a stable stub
        // until the comment service exposes per-user totals.
        let postKarma = posts.reduce(0) { $0 + max($1.score, 0) }
        return Profile(
            user: Session.me,
            postKarma: postKarma,
            commentKarma: 642,
            joinedCommunities: joined,
            posts: posts
        )
    }
}
