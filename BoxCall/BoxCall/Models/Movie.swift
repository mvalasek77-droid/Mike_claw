import Foundation

struct Movie: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let studio: String
    let releaseDate: Date
    let posterEmoji: String        // placeholder; real app would use TMDB poster URL
    let tagline: String
    let consensusOpeningMillions: Double  // crowd/tracker estimate
    let impliedVolPct: Double      // 0-100, drives premium pricing
    let genre: String

    var daysToRelease: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: releaseDate)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }

    var isSettled: Bool {
        // Opening weekend settles the Monday after release
        Date() > releaseDate.addingTimeInterval(3 * 86400)
    }
}
