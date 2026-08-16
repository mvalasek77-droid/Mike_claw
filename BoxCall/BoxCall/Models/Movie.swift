import Foundation

struct Movie: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let studio: String
    let releaseDate: Date
    let posterEmoji: String            // fallback identifier
    let posterURL: String?             // real poster from TMDB / provider
    let tagline: String
    let consensusOpeningMillions: Double
    let impliedVolPct: Double
    let genre: String
    let addedAt: Date                  // for "NEW" badge on Slate

    init(
        id: String,
        title: String,
        studio: String,
        releaseDate: Date,
        posterEmoji: String,
        posterURL: String? = nil,
        tagline: String,
        consensusOpeningMillions: Double,
        impliedVolPct: Double,
        genre: String,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.studio = studio
        self.releaseDate = releaseDate
        self.posterEmoji = posterEmoji
        self.posterURL = posterURL
        self.tagline = tagline
        self.consensusOpeningMillions = consensusOpeningMillions
        self.impliedVolPct = impliedVolPct
        self.genre = genre
        self.addedAt = addedAt
    }

    var daysToRelease: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: releaseDate)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }

    var isSettled: Bool {
        Date() > releaseDate.addingTimeInterval(3 * 86400)
    }

    var isNewlyAdded: Bool {
        Date().timeIntervalSince(addedAt) < 48 * 3600
    }
}
