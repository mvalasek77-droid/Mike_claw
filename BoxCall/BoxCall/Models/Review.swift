import Foundation

/// A short-form written take on a movie — Letterboxd-style.
/// Top-5 leaderboard performers get their latest review spotlighted.
struct Review: Identifiable, Codable, Hashable {
    let id: UUID
    let authorHandle: String
    let authorTier: Tier
    let authorIsCurrentUser: Bool
    let movieId: String
    let movieTitle: String
    let moviePosterEmoji: String
    let headline: String       // one-line hook
    let body: String           // full review
    let rating: Int            // 0-5 (stars), or -1 to mean "not applicable pre-release"
    let createdAt: Date
    var likes: Int
    var isLikedByMe: Bool

    var stars: String {
        guard rating >= 0 else { return "•" }
        return String(repeating: "★", count: rating) + String(repeating: "☆", count: max(0, 5 - rating))
    }
}
