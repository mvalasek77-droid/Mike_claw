import Foundation
import Combine

/// The feed. Predictions become posts; posts get likes, comments, follows.
final class SocialService: ObservableObject {
    static let shared = SocialService()

    @Published private(set) var feed: [SocialPost] = []
    @Published private(set) var reviews: [Review] = []
    /// Position id -> post id, so settlement can update the outcome on the post.
    private var postByPositionId: [UUID: UUID] = [:]

    private init() {
        seedFeed()
        seedReviews()
    }

    // MARK: - Reviews

    /// Latest reviews by the current top-5 leaderboard performers, in leaderboard order.
    /// Falls back to any reviews if no leaderboard match.
    func spotlightedReviews() -> [Review] {
        let topHandles = PortfolioService.shared.leaderboard.prefix(5).map(\.handle)
        var picked: [Review] = []
        for handle in topHandles {
            if let r = reviews
                .filter({ $0.authorHandle == handle })
                .sorted(by: { $0.createdAt > $1.createdAt })
                .first {
                picked.append(r)
            }
        }
        return picked
    }

    func submitReview(movie: Movie, headline: String, body: String, rating: Int) {
        let user = PortfolioService.shared.user
        let review = Review(
            id: UUID(),
            authorHandle: user.handle,
            authorTier: user.tier,
            authorIsCurrentUser: true,
            movieId: movie.id,
            movieTitle: movie.title,
            moviePosterEmoji: movie.posterEmoji,
            headline: headline,
            body: body,
            rating: rating,
            createdAt: Date(),
            likes: 0,
            isLikedByMe: false
        )
        reviews.insert(review, at: 0)
    }

    func toggleReviewLike(id: UUID) {
        guard let idx = reviews.firstIndex(where: { $0.id == id }) else { return }
        reviews[idx].isLikedByMe.toggle()
        reviews[idx].likes += reviews[idx].isLikedByMe ? 1 : -1
    }

    func reviews(for movieId: String) -> [Review] {
        reviews.filter { $0.movieId == movieId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func latestReview(byHandle handle: String) -> Review? {
        reviews.filter { $0.authorHandle == handle }
            .sorted { $0.createdAt > $1.createdAt }.first
    }

    private func seedReviews() {
        let m = MarketService.shared
        guard let starmap = m.movie(id: "m_starmap"),
              let neon    = m.movie(id: "m_neon"),
              let atlas   = m.movie(id: "m_atlas"),
              let prowl   = m.movie(id: "m_prowl"),
              let glacier = m.movie(id: "m_glacier"),
              let paper   = m.movie(id: "m_paperhouse") else { return }

        reviews = [
            .init(id: UUID(), authorHandle: "popcornshark", authorTier: .studioHead,
                  authorIsCurrentUser: false,
                  movieId: starmap.id, movieTitle: starmap.title, moviePosterEmoji: starmap.posterEmoji,
                  headline: "The universe expands. My interest doesn't.",
                  body: "By the fifth Starmap the ceiling is visible — you can see where the cape flutters, where the joke was written, where the reshoots patched a plot hole with a monologue. Tracking still thinks $168M because the brand carries it, but presales are soft in the top-25 and the trailer's Rotten Tomatoes leak reads like an obituary. Fading calls at $155.",
                  rating: 2, createdAt: Date().addingTimeInterval(-3600 * 4),
                  likes: 312, isLikedByMe: false),
            .init(id: UUID(), authorHandle: "indieyoda", authorTier: .producer,
                  authorIsCurrentUser: false,
                  movieId: neon.id, movieTitle: neon.title, moviePosterEmoji: neon.posterEmoji,
                  headline: "The sleeper of the season.",
                  body: "A24 knows what it's doing. Letterboxd early reviews are averaging 4.1, TikTok's discovered the soundtrack, and the trailer is doing quiet numbers with high completion rates — the tell. Consensus $12M is a floor, not a ceiling. I'm long calls at every strike up to $18M.",
                  rating: 4, createdAt: Date().addingTimeInterval(-3600 * 8),
                  likes: 187, isLikedByMe: true),
            .init(id: UUID(), authorHandle: "openingnight", authorTier: .insider,
                  authorIsCurrentUser: false,
                  movieId: atlas.id, movieTitle: atlas.title, moviePosterEmoji: atlas.posterEmoji,
                  headline: "Old-fashioned in the best way.",
                  body: "Two hours and eighteen minutes of a movie that trusts its audience. Adult drama sold on movie-star charisma — a lost art. Warner marketing has been quiet, which usually means confidence. Consensus $58M feels ten million light to me.",
                  rating: 4, createdAt: Date().addingTimeInterval(-3600 * 12),
                  likes: 94, isLikedByMe: false),
            .init(id: UUID(), authorHandle: "marqueemaven", authorTier: .insider,
                  authorIsCurrentUser: false,
                  movieId: prowl.id, movieTitle: prowl.title, moviePosterEmoji: prowl.posterEmoji,
                  headline: "Buried alive by its own studio.",
                  body: "Blumhouse released three genre movies this month. Guess which one the marketing team gave up on? Prowl gets a promo push worth about seven dollars and a poster. Consensus $21M is fantasy — this opens single digits and I'll take the Bomb Caller badge, thanks.",
                  rating: 2, createdAt: Date().addingTimeInterval(-3600 * 18),
                  likes: 71, isLikedByMe: false),
            .init(id: UUID(), authorHandle: "greenlight", authorTier: .analyst,
                  authorIsCurrentUser: false,
                  movieId: glacier.id, movieTitle: glacier.title, moviePosterEmoji: glacier.posterEmoji,
                  headline: "Solid thriller in a soft weekend.",
                  body: "Universal did their homework on the marketing. Adult thrillers in the $30-40M range have overperformed all year. Nothing to short here; nothing to blow the doors off either. Consensus $34M is fair.",
                  rating: 3, createdAt: Date().addingTimeInterval(-3600 * 24),
                  likes: 44, isLikedByMe: false),
            .init(id: UUID(), authorHandle: "trailerbait", authorTier: .analyst,
                  authorIsCurrentUser: false,
                  movieId: paper.id, movieTitle: paper.title, moviePosterEmoji: paper.posterEmoji,
                  headline: "Searchlight prestige on autopilot.",
                  body: "You've seen this movie before. Sometimes that's a compliment. The tracking is honest; the audience is loyal; the theatrical run will be short and the streaming tail will pay the bills. Neutral.",
                  rating: 3, createdAt: Date().addingTimeInterval(-3600 * 30),
                  likes: 18, isLikedByMe: false)
        ]
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
