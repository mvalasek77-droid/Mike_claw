import Foundation
import Combine

/// The feed. Predictions become posts; posts get likes, comments, follows.
final class SocialService: ObservableObject {
    static let shared = SocialService()

    @Published private(set) var feed: [SocialPost] = []
    /// Position id -> post id, so settlement can update the outcome on the post.
    private var postByPositionId: [UUID: UUID] = [:]

    private init() {
        seedFeed()
    }

    // MARK: - Publishing

    /// Turn a placed trade into a public post.
    func share(positionId: UUID, contract: Contract, movie: Movie, quantity: Int, hotTake: String?) {
        let user = PortfolioService.shared.user
        let post = SocialPost(
            id: UUID(),
            authorHandle: user.handle,
            authorTier: user.tier,
            authorIsCurrentUser: true,
            movieId: movie.id,
            movieTitle: movie.title,
            moviePosterEmoji: movie.posterEmoji,
            side: contract.side,
            strikeMillions: contract.strikeMillions,
            quantity: quantity,
            entryPremium: contract.premium,
            hotTake: hotTake?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : hotTake,
            createdAt: Date(),
            likes: 0,
            isLikedByMe: false,
            comments: [],
            outcome: nil
        )
        feed.insert(post, at: 0)
        postByPositionId[positionId] = post.id
    }

    func attachOutcome(positionId: UUID, actual: Double, payoutPerContract: Double, netProfit: Double) {
        guard let postId = postByPositionId[positionId],
              let idx = feed.firstIndex(where: { $0.id == postId }) else { return }
        feed[idx].outcome = .init(
            actualMillions: actual,
            payoutPerContract: payoutPerContract,
            netProfit: netProfit
        )
        if netProfit > 0 {
            feed[idx].likes += Int.random(in: 12...50)  // outcome brings traffic
        }
    }

    // MARK: - Interactions

    func toggleLike(postId: UUID) {
        guard let idx = feed.firstIndex(where: { $0.id == postId }) else { return }
        feed[idx].isLikedByMe.toggle()
        feed[idx].likes += feed[idx].isLikedByMe ? 1 : -1
    }

    func addComment(postId: UUID, body: String) {
        guard let idx = feed.firstIndex(where: { $0.id == postId }) else { return }
        let user = PortfolioService.shared.user
        feed[idx].comments.append(.init(
            id: UUID(),
            authorHandle: user.handle,
            authorTier: user.tier,
            body: body,
            createdAt: Date()
        ))
    }

    func follow(handle: String) {
        PortfolioService.shared.mutateUser { $0.followingHandles.insert(handle) }
    }

    func unfollow(handle: String) {
        PortfolioService.shared.mutateUser { $0.followingHandles.remove(handle) }
    }

    func isFollowing(_ handle: String) -> Bool {
        PortfolioService.shared.user.followingHandles.contains(handle)
    }

    // MARK: - Mock seed

    private func seedFeed() {
        let market = MarketService.shared
        guard let starmap = market.movie(id: "m_starmap"),
              let neon    = market.movie(id: "m_neon"),
              let atlas   = market.movie(id: "m_atlas"),
              let prowl   = market.movie(id: "m_prowl") else { return }

        feed = [
            .init(id: UUID(), authorHandle: "popcornshark", authorTier: .studioHead,
                  authorIsCurrentUser: false,
                  movieId: starmap.id, movieTitle: starmap.title, moviePosterEmoji: starmap.posterEmoji,
                  side: .put, strikeMillions: 155, quantity: 20, entryPremium: 6.20,
                  hotTake: "Rotten reviews out of the premiere. Fatigue is real — trims 12–18M off tracking.",
                  createdAt: Date().addingTimeInterval(-3600),
                  likes: 214, isLikedByMe: false,
                  comments: [
                    .init(id: UUID(), authorHandle: "indieyoda", authorTier: .producer,
                          body: "Bold with $155 as the strike. I like it.", createdAt: Date().addingTimeInterval(-1800))
                  ],
                  outcome: nil),
            .init(id: UUID(), authorHandle: "indieyoda", authorTier: .producer,
                  authorIsCurrentUser: false,
                  movieId: neon.id, movieTitle: neon.title, moviePosterEmoji: neon.posterEmoji,
                  side: .call, strikeMillions: 12, quantity: 40, entryPremium: 2.80,
                  hotTake: "A24 sleeper. Letterboxd is heating up faster than tracking suggests.",
                  createdAt: Date().addingTimeInterval(-7200),
                  likes: 88, isLikedByMe: false, comments: [], outcome: nil),
            .init(id: UUID(), authorHandle: "greenlight", authorTier: .analyst,
                  authorIsCurrentUser: false,
                  movieId: atlas.id, movieTitle: atlas.title, moviePosterEmoji: atlas.posterEmoji,
                  side: .call, strikeMillions: 62, quantity: 15, entryPremium: 5.10,
                  hotTake: nil,
                  createdAt: Date().addingTimeInterval(-10_800),
                  likes: 12, isLikedByMe: false, comments: [], outcome: nil),
            .init(id: UUID(), authorHandle: "marqueemaven", authorTier: .insider,
                  authorIsCurrentUser: false,
                  movieId: prowl.id, movieTitle: prowl.title, moviePosterEmoji: prowl.posterEmoji,
                  side: .put, strikeMillions: 18, quantity: 25, entryPremium: 3.40,
                  hotTake: "Blumhouse over-saturated this month. Prowl gets buried.",
                  createdAt: Date().addingTimeInterval(-14_400),
                  likes: 41, isLikedByMe: true, comments: [], outcome: nil)
        ]
    }
}
