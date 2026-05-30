import SwiftUI

/// The three media categories the marketplace trades in.
enum MediaType: String, CaseIterable, Identifiable, Hashable, Codable {
    case novel, music, movie
    var id: String { rawValue }

    var title: String {
        switch self {
        case .novel: return "Novel"
        case .music: return "Album"
        case .movie: return "Film"
        }
    }

    var plural: String {
        switch self {
        case .novel: return "Novels"
        case .music: return "Music"
        case .movie: return "Films"
        }
    }

    var icon: String {
        switch self {
        case .novel: return "book.closed.fill"
        case .music: return "music.note"
        case .movie: return "film.fill"
        }
    }

    /// The consumption verb shown on the action button.
    var verb: String {
        switch self {
        case .novel: return "Read"
        case .music: return "Listen"
        case .movie: return "Watch"
        }
    }

    var accent: Color {
        switch self {
        case .novel: return Color(red: 0.98, green: 0.62, blue: 0.18)
        case .music: return Color(red: 0.74, green: 0.36, blue: 0.98)
        case .movie: return Color(red: 0.30, green: 0.62, blue: 1.00)
        }
    }

    /// Label used for the "length" metadata line on a detail screen.
    func lengthNoun(_ value: Int) -> String {
        switch self {
        case .novel: return "\(value) page\(value == 1 ? "" : "s")"
        case .music: return "\(value) track\(value == 1 ? "" : "s")"
        case .movie: return "\(value) min"
        }
    }
}

/// A live, accepted piece of media available in the marketplace.
struct MediaItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var creator: String
    var type: MediaType
    var genre: String
    var synopsis: String
    /// Which AI systems produced the work (creator-disclosed).
    var aiTools: [String]
    /// AI Editor commercial-readiness score, 0–100.
    var commercialScore: Int
    var price: Double
    var releaseYear: Int
    /// Pages / tracks / minutes depending on `type`.
    var length: Int
    var maturity: String
    /// Lifetime purchases — drives the Top 10.
    var purchases: Int
    /// 0–100 momentum metric — drives Trending.
    var trending: Int
    var addedAt: Date
    /// Creator-supplied cover art (encoded image) for published titles.
    var coverImageData: Data?
    /// Bundled cover-art asset name for seed catalogue titles.
    var coverAssetName: String?
    /// Bundled playable media file (audio/video) for seed catalogue titles.
    var mediaFileName: String?
    /// True when the AI Editor produced this title itself to fill open space in
    /// the catalogue (no creator upload). Surfaced transparently in the UI.
    var isEditorOriginal: Bool

    init(
        id: UUID = UUID(),
        title: String,
        creator: String,
        type: MediaType,
        genre: String,
        synopsis: String,
        aiTools: [String],
        commercialScore: Int,
        price: Double,
        releaseYear: Int = 2026,
        length: Int,
        maturity: String = "13+",
        purchases: Int = 0,
        trending: Int = 0,
        addedAt: Date = .now,
        coverImageData: Data? = nil,
        coverAssetName: String? = nil,
        mediaFileName: String? = nil,
        isEditorOriginal: Bool = false
    ) {
        self.id = id
        self.title = title
        self.creator = creator
        self.type = type
        self.genre = genre
        self.synopsis = synopsis
        self.aiTools = aiTools
        self.commercialScore = commercialScore
        self.price = price
        self.releaseYear = releaseYear
        self.length = length
        self.maturity = maturity
        self.purchases = purchases
        self.trending = trending
        self.addedAt = addedAt
        self.coverImageData = coverImageData
        self.coverAssetName = coverAssetName
        self.mediaFileName = mediaFileName
        self.isEditorOriginal = isEditorOriginal
    }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var priceLabel: String { String(format: "$%.2f", price) }
    var lengthLabel: String { type.lengthNoun(length) }
    var scoreLabel: String { "\(commercialScore)/100" }

    /// A short, human "grade" for the commercial score badge.
    var grade: String {
        switch commercialScore {
        case 95...: return "Flagship"
        case 90..<95: return "Commercial+"
        case 85..<90: return "Commercial"
        default: return "Below bar"
        }
    }
}

/// Stable, launch-independent hash used to seed procedural artwork.
func stableHash(_ string: String) -> Int {
    var hash = 5381
    for byte in string.utf8 { hash = (hash &* 33) &+ Int(byte) }
    return abs(hash)
}

extension MediaItem {
    var seed: Int { stableHash(id.uuidString + title) }
}

/// Curated AI-tool suggestions surfaced in the disclosure step, grouped by
/// the kind of media they typically generate.
enum AIToolCatalog {
    /// Operator-supplied model list from the Scout feed, when one has been
    /// fetched. Wins over the bundled fallback below so the picker reflects
    /// today's catalogue (GPT-5, Sora 2, etc.) rather than ship-day's list.
    private(set) static var feedModels: [String] = []

    static func applyFeedModels(_ models: [String]) {
        feedModels = models
    }

    /// Every model the marketplace knows about, across all media types.
    static var allModels: [String] {
        if !feedModels.isEmpty { return feedModels }
        return MediaType.allCases.flatMap { suggestions(for: $0) }
    }

    /// The media type a given model produces (first match wins). Uses the
    /// bundled categorisation; the feed list is flat so we fall back here.
    static func type(for tool: String) -> MediaType? {
        MediaType.allCases.first { suggestions(for: $0).contains(tool) }
    }

    static func suggestions(for type: MediaType) -> [String] {
        switch type {
        case .novel:
            return ["Claude Opus 4.7", "GPT-4", "Gemini", "Llama 3", "Mistral Large"]
        case .music:
            return ["Suno", "Udio", "Stable Audio", "ElevenLabs"]
        case .movie:
            return ["Sora", "Runway", "Google Veo", "Kling", "Pika"]
        }
    }
}
