import Foundation
import Combine

/// Global sheet driver so any view can pop the TradeSheet pre-filled
/// (used by the "Copy call" action on feed posts).
final class TradeCoordinator: ObservableObject {
    static let shared = TradeCoordinator()

    @Published var pendingCopy: CopyIntent?

    struct CopyIntent: Identifiable, Hashable {
        let id: UUID
        let contract: Contract
        let movie: Movie
    }

    private init() {}

    /// Match the source post to a live contract in the current chain.
    /// Returns nil if the movie has settled or the chain no longer exposes
    /// that strike/side.
    func requestCopy(fromPost post: SocialPost) -> Bool {
        guard let movie = MarketService.shared.movie(id: post.movieId),
              !movie.isSettled else { return false }

        let chain = MarketService.shared.chain(for: post.movieId)
        guard let match = chain.first(where: {
            $0.side == post.side &&
            abs($0.strikeMillions - post.strikeMillions) < 0.01
        }) else { return false }

        pendingCopy = .init(id: UUID(), contract: match, movie: movie)
        return true
    }
}
