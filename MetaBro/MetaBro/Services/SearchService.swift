import Foundation

struct SearchResults: Sendable, Equatable {
    var communities: [Community]
    var posts: [Post]

    var isEmpty: Bool { communities.isEmpty && posts.isEmpty }
    static let none = SearchResults(communities: [], posts: [])
}

protocol SearchService: Sendable {
    func search(_ query: String) async throws -> SearchResults
}

/// Case-insensitive substring search over the same mock data the feed and
/// communities use, so results stay consistent across the app.
struct MockSearchService: SearchService {
    let feedService: FeedService
    let communityService: CommunityService

    func search(_ query: String) async throws -> SearchResults {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return .none }

        async let allPosts = feedService.feed(sort: .new, cursor: nil).posts
        async let allCommunities = communityService.discover()

        let posts = try await allPosts.filter {
            ($0.title?.lowercased().contains(q) ?? false)
            || $0.body.lowercased().contains(q)
            || ($0.community?.name.lowercased().contains(q) ?? false)
        }
        let communities = try await allCommunities.filter {
            $0.name.lowercased().contains(q) || $0.slug.lowercased().contains(q)
        }
        return SearchResults(communities: communities, posts: posts)
    }
}
