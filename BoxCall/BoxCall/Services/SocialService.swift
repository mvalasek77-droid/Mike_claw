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
        // Pick any real movie ids that are in the seed; skip missing.
        let picks = m.movies.prefix(6)
        var out: [Review] = []
        let seedPacks: [(String, Tier, String, String, Int, Int, Bool)] = [
            ("popcornshark",  .studioHead, "Franchise fatigue is a real number.",
             "This one carries the tentpole load for the quarter. Presales are strong in the top-25 markets but softer in the flyover, and the trailer's Rotten Tomatoes leak reads middling. I'd fade the highest strikes and buy the mid-body.",
             312, 4, false),
            ("indieyoda",     .producer,   "Underestimated. Again.",
             "The tracking model doesn't know how to price this. Letterboxd early reviews are running hot and the marketing pivot in the last two weeks landed. Consensus feels ten to fifteen million light.",
             187, 8, true),
            ("openingnight",  .insider,    "Old-fashioned in the best way.",
             "The audience for this shows up. Adult drama sold on movie-star charisma — a lost art. The studio's been quiet in press which usually means confidence. I'm long the money strike.",
             94,  12, false),
            ("marqueemaven",  .insider,    "Great trailer, no reason to see it opening weekend.",
             "Streaming will absorb this in three weeks. The core audience already knows the plot from the marketing. Not a bomb — just a slow build.",
             71,  18, false),
            ("greenlight",    .analyst,    "Priced fairly. Not much edge either way.",
             "Genre plays in this budget range have overperformed all year. Nothing to short; nothing to swing for the fence on. Consensus is honest.",
             44,  24, false),
            ("trailerbait",   .analyst,    "Prestige on autopilot.",
             "You've seen this movie before. Sometimes that's a compliment. The tracking is honest; the audience is loyal; the theatrical run will be short. Neutral.",
             18,  30, false),
        ]
        for (pack, movie) in zip(seedPacks, picks) {
            out.append(.init(
                id: UUID(),
                authorHandle: pack.0, authorTier: pack.1,
                authorIsCurrentUser: false,
                movieId: movie.id, movieTitle: movie.title,
                moviePosterEmoji: movie.posterEmoji,
                headline: pack.2, body: pack.3, rating: pack.5 == 0 ? 3 : min(5, pack.5),
                createdAt: Date().addingTimeInterval(-3600 * Double(pack.5)),
                likes: pack.4, isLikedByMe: pack.6
            ))
        }
        reviews = out
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
        // Adapt to whichever movies the market catalog exposes right
        // now — real TMDB fetch, mock seed, or something in between.
        let movies = MarketService.shared.movies.prefix(4)
        guard !movies.isEmpty else { return }
        let seeds: [(String, Tier, ContractSide, Double, Int, Double, String?, Int, Bool)] = [
            ("popcornshark", .studioHead, .put,  Double(Int(movies.first?.consensusOpeningMillions ?? 60) - 5),
             20, 6.20, "Tracking looks generous. Fading strength.", 214, false),
            ("indieyoda",    .producer,   .call, Double(Int(movies.dropFirst().first?.consensusOpeningMillions ?? 20)),
             40, 2.80, "Letterboxd is heating up faster than tracking suggests.", 88, false),
            ("greenlight",   .analyst,    .call, Double(Int(movies.dropFirst(2).first?.consensusOpeningMillions ?? 40) + 4),
             15, 5.10, nil, 12, false),
            ("marqueemaven", .insider,    .put,  Double(Int(movies.dropFirst(3).first?.consensusOpeningMillions ?? 20) - 3),
             25, 3.40, "Marketing was too quiet. Getting buried.", 41, true),
        ]
        feed = zip(seeds, movies).map { seed, movie in
            SocialPost(
                id: UUID(), authorHandle: seed.0, authorTier: seed.1,
                authorIsCurrentUser: false,
                movieId: movie.id, movieTitle: movie.title,
                moviePosterEmoji: movie.posterEmoji,
                side: seed.2, strikeMillions: seed.3,
                quantity: seed.4, entryPremium: seed.5,
                hotTake: seed.6,
                createdAt: Date().addingTimeInterval(-Double(seed.7 * 30)),
                likes: seed.7, isLikedByMe: seed.8,
                comments: [], outcome: nil
            )
        }
    }
}
