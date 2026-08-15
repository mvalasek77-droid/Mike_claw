import Foundation

/// News/tracking events that shock a movie's whole chain.
/// Positive `magnitude` = bullish for the movie (raises Call marks, drops Put marks).
struct MarketEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let time: Date
    let movieId: String
    let movieTitle: String
    let headline: String
    let magnitude: Double     // -1 ... +1

    var isBullish: Bool { magnitude > 0 }

    static let bullishHeadlines: [String] = [
        "Presales spike — 60% ahead of tracking",
        "First reactions land: 94% Rotten Tomatoes at premiere",
        "Trailer #2 crosses 30M views in 24 hours",
        "TikTok trend blows up around the marketing",
        "Star does surprise arena appearance"
    ]
    static let bearishHeadlines: [String] = [
        "Embargo lifts: reviews weaker than tracking assumed",
        "Rival studio moves competitor into same weekend",
        "Producer's on-camera comment goes viral (badly)",
        "Presales soft in top-25 markets",
        "Runtime leak — 2h48m sparks backlash"
    ]
}
