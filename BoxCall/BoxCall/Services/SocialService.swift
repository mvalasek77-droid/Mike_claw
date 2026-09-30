import Foundation
import Combine

/// The feed. Predictions become posts; posts get likes, comments, follows.
@MainActor
final class SocialService: ObservableObject {
    static let shared = SocialService()

    @Published private(set) var feed: [SocialPost] = [] { didSet { persist() } }
    @Published private(set) var reviews: [Review] = [] { didSet { persist() } }
    /// Position id -> post id, so settlement can update the outcome on the post.
    private var postByPositionId: [UUID: UUID] = [:] { didSet { persist() } }

    /// The current user's own posts and reviews. Rivals' content is re-seeded each launch.
    private struct Saved: Codable {
        var posts: [SocialPost]
        var reviews: [Review]
        var postByPositionId: [UUID: UUID]
    }

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("social.json")
    }

    /// Blocks writes until the saved file is merged in, so seeding can't overwrite it.
    private var isLoaded = false

    private init() {
        seedFeed()
        seedReviews()
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            feed = saved.posts + feed
            reviews = saved.reviews + reviews
            postByPositionId = saved.postByPositionId
        }
        isLoaded = true
    }

    private func persist() {
        guard isLoaded else { return }
        let saved = Saved(posts: feed.filter(\.authorIsCurrentUser),
                          reviews: reviews.filter(\.authorIsCurrentUser),
                          postByPositionId: postByPositionId)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory,
                                                 withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func removeCurrentUserContent() {
        let me = PortfolioService.shared.user.handle
        for i in feed.indices { feed[i].comments.removeAll { $0.authorHandle == me } }
        feed.removeAll { $0.authorIsCurrentUser }
        reviews.removeAll { $0.authorIsCurrentUser }
        postByPositionId.removeAll()
    }

    // MARK: - Reviews

    /// Latest review by each of the top 5 traders by total profit, in rank
    /// order — the most profitable trader with a review leads the homepage.
    func spotlightedReviews() -> [Review] {
        PortfolioService.shared.leaderboard.prefix(5).compactMap { latestReview(for: $0) }
    }

    /// Leaderboard rank (1-based) of a review's author, if they're ranked.
    func rank(ofAuthorOf review: Review) -> Int? {
        PortfolioService.shared.leaderboard.firstIndex { entry in
            entry.isCurrentUser ? review.authorIsCurrentUser
                                : (!review.authorIsCurrentUser && entry.handle == review.authorHandle)
        }.map { $0 + 1 }
    }

    var hasCurrentUserReview: Bool { reviews.contains(where: \.authorIsCurrentUser) }

    /// A trader's rank now. Ranks move with profit, so the rank saved on an
    /// old post or review is only a fallback for handles off the leaderboard.
    func liveTier(handle: String, isCurrentUser: Bool, saved: Tier) -> Tier {
        let portfolio = PortfolioService.shared
        if isCurrentUser { return portfolio.user.tier }
        return portfolio.leaderboard.first { !$0.isCurrentUser && $0.handle == handle }?.tier ?? saved
    }

    private func latestReview(for entry: LeaderboardEntry) -> Review? {
        // Match the current user by flag, not handle: signing in can rename them.
        reviews
            .filter { entry.isCurrentUser ? $0.authorIsCurrentUser
                                          : (!$0.authorIsCurrentUser && $0.authorHandle == entry.handle) }
            .max { $0.createdAt < $1.createdAt }
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
        SentimentEngine.shared.recordReview(movieId: movie.id,
                                            rating: rating,
                                            handle: user.handle)
    }

    func toggleReviewLike(id: UUID) {
        guard let idx = reviews.firstIndex(where: { $0.id == id }) else { return }
        reviews[idx].isLikedByMe.toggle()
        reviews[idx].likes = max(0, reviews[idx].likes + (reviews[idx].isLikedByMe ? 1 : -1))
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
        // Opinions only: these are pinned to whichever films are listed,
        // so they never state a fact (presales, scores, tracking) about one.
        let seedPacks: [(String, Tier, String, String, Int, Int)] = [
            ("popcornshark",  .studioHead, "Priced for a perfect weekend.",
             "The chain is pricing the best case. I'd fade the highest strikes and buy the middle of the range — a solid opening still pays there.",
             4, 4),
            ("indieyoda",     .producer,   "The crowd is too cautious.",
             "Consensus feels light to me. Films like this tend to find their audience faster than the market assumes. I'm long a strike above consensus.",
             8, 5),
            ("openingnight",  .insider,    "Old-fashioned in the best way.",
             "The audience for this kind of movie still exists, and it buys tickets opening weekend. I'm long the money strike.",
             12, 4),
            ("marqueemaven",  .insider,    "Great trailer, no rush to see it.",
             "I think plenty of people wait for streaming on this one. Not a bomb — just a slow build. Small put below consensus.",
             18, 3),
            ("greenlight",    .analyst,    "Priced fairly. Not much edge either way.",
             "I don't see an edge on either side at these prices. Nothing to short, nothing to swing for. Sitting this one out.",
             24, 3),
            ("trailerbait",   .analyst,    "Prestige on autopilot.",
             "You've seen this movie before. Sometimes that's a compliment. I expect a steady opening, not a surprise. Neutral.",
             30, 3),
        ]
        for (pack, movie) in zip(seedPacks, picks) {
            out.append(.init(
                id: UUID(),
                authorHandle: pack.0, authorTier: pack.1,
                authorIsCurrentUser: false,
                movieId: movie.id, movieTitle: movie.title,
                moviePosterEmoji: movie.posterEmoji,
                headline: pack.2, body: pack.3, rating: pack.5,
                createdAt: Date().addingTimeInterval(-3600 * Double(pack.4)),
                likes: 0, isLikedByMe: false
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
        // A public Hot Take is crowd chatter the desk quotes against.
        SentimentEngine.shared.recordHotTake(movieId: movie.id,
                                             side: contract.side,
                                             handle: user.handle)
    }

    func attachOutcome(positionId: UUID, actual: Double, payoutPerContract: Double, netProfit: Double) {
        guard let postId = postByPositionId[positionId],
              let idx = feed.firstIndex(where: { $0.id == postId }) else { return }
        feed[idx].outcome = .init(
            actualMillions: actual,
            payoutPerContract: payoutPerContract,
            netProfit: netProfit
        )
    }

    // MARK: - Interactions

    func toggleLike(postId: UUID) {
        guard let idx = feed.firstIndex(where: { $0.id == postId }) else { return }
        feed[idx].isLikedByMe.toggle()
        feed[idx].likes = max(0, feed[idx].likes + (feed[idx].isLikedByMe ? 1 : -1))
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
        // now — live TMDB fetch, verified offline slate, or a mix.
        let movies = MarketService.shared.movies.prefix(4)
        guard !movies.isEmpty else { return }
        // (handle, rank, side, strike, quantity, premium, hot take, minutes ago)
        let seeds: [(String, Tier, ContractSide, Double, Int, Double, String?, Int)] = [
            ("popcornshark", .studioHead, .put,  Double(Int(movies.first?.consensusOpeningMillions ?? 60) - 5),
             20, 6.20, "Consensus looks generous to me. Fading strength.", 107),
            ("indieyoda",    .producer,   .call, Double(Int(movies.dropFirst().first?.consensusOpeningMillions ?? 20)),
             40, 2.80, "I think the market is too low on this one.", 44),
            ("greenlight",   .analyst,    .call, Double(Int(movies.dropFirst(2).first?.consensusOpeningMillions ?? 40) + 4),
             15, 5.10, nil, 6),
            ("marqueemaven", .insider,    .put,  Double(Int(movies.dropFirst(3).first?.consensusOpeningMillions ?? 20) - 3),
             25, 3.40, "Feels like it gets lost on a crowded weekend.", 20),
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
                createdAt: Date().addingTimeInterval(-Double(seed.7 * 60)),
                likes: 0, isLikedByMe: false,
                comments: [], outcome: nil
            )
        }
    }
}
