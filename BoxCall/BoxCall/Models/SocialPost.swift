import Foundation

struct SocialPost: Identifiable, Codable, Hashable {
    let id: UUID
    let authorHandle: String
    let authorTier: Tier
    let authorIsCurrentUser: Bool
    let movieId: String
    let movieTitle: String
    let moviePosterEmoji: String
    let side: ContractSide
    let strikeMillions: Double
    let quantity: Int
    let entryPremium: Double
    let hotTake: String?
    let createdAt: Date

    var likes: Int
    var isLikedByMe: Bool
    var comments: [Comment]

    /// Post updates once the underlying trade settles.
    var outcome: PostOutcome?

    struct PostOutcome: Codable, Hashable {
        let actualMillions: Double
        let payoutPerContract: Double
        let netProfit: Double
    }
}

struct Comment: Identifiable, Codable, Hashable {
    let id: UUID
    let authorHandle: String
    let authorTier: Tier
    let body: String
    let createdAt: Date
}
