import SwiftUI

/// The three media categories the marketplace trades in.
enum MediaType: String, CaseIterable, Identifiable, Hashable, Codable {
    case novel, music, movie
    var id: String { rawValue }

    var title: String {
        switch self {
        case .novel: return "Novel"
        case .music: return "Music"
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
        case .music: return value == 1 ? "Single" : "\(value) tracks"
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
    /// User-uploaded media file copied into the app's Documents directory at
    /// publish time. `mediaFileName` is for bundled sample assets; this is
    /// for content the buyer paid for so playback resolves to a real file
    /// instead of falling through to SimulatedTransport. Just the basename
    /// (e.g. "ABC123.mp3") — the directory is `Documents/published/`.
    var localMediaFileName: String? = nil
    /// Full manuscript text for a user-published novel. Carried directly on
    /// the MediaItem so the reader doesn't have to look it up via the
    /// security-scoped URL after publish (that URL dies with the picker).
    var manuscriptText: String? = nil
    /// True when the AI Editor produced this title itself to fill open space in
    /// the catalogue (no creator upload). Surfaced transparently in the UI.
    var isEditorOriginal: Bool
    /// True when the cover artwork already has the title baked in (typical of
    /// album art / movie posters). PosterArt suppresses its own title overlay
    /// when this is on, so the same title doesn't render twice on top of the
    /// artwork. Defaults to false; opt-in per asset.
    var coverHasTitle: Bool = false
    /// Scout-drafted screenplay scenes, in order. Each scene is 2–5 minutes
    /// of runtime; the film accumulates scenes over Scout cycles until the
    /// total runtime reaches `targetMinutes`. Empty for user-uploaded films
    /// (those carry video bytes via `mediaFileName`).
    var screenplayScenes: [String] = []
    /// Minutes-per-scene, parallel to `screenplayScenes`. Each entry is 2–5.
    var sceneDurations: [Int] = []
    /// Minimum runtime a Scout film grows to. 30 means "30+ min when complete."
    var targetMinutes: Int = 0
    /// Optional remote video URL per scene, parallel to `screenplayScenes`.
    /// Empty string means "screenplay only" (no real video bytes yet). Once a
    /// provider call lands an mp4 for scene N, the URL goes here.
    var sceneVideoURLs: [String] = []

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
        isEditorOriginal: Bool = false,
        localMediaFileName: String? = nil,
        manuscriptText: String? = nil,
        coverHasTitle: Bool = false,
        screenplayScenes: [String] = [],
        sceneDurations: [Int] = [],
        targetMinutes: Int = 0,
        sceneVideoURLs: [String] = []
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
        self.localMediaFileName = localMediaFileName
        self.manuscriptText = manuscriptText
        self.coverHasTitle = coverHasTitle
        self.screenplayScenes = screenplayScenes
        self.sceneDurations = sceneDurations
        self.targetMinutes = targetMinutes
        self.sceneVideoURLs = sceneVideoURLs
    }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Total runtime across accumulated scenes, in minutes.
    var totalSceneMinutes: Int { sceneDurations.reduce(0, +) }
    /// True when this is a Scout-built film still accumulating scenes toward target.
    var isFilmInProgress: Bool {
        type == .movie && totalSceneMinutes < targetMinutes && !screenplayScenes.isEmpty
    }
    /// True when a Scout film has reached its target runtime.
    var isFilmComplete: Bool {
        type == .movie && targetMinutes > 0 && totalSceneMinutes >= targetMinutes
    }

    /// Tolerant decode so titles saved before the segmented-film model still
    /// load — new fields default to empty / 1.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.creator = try c.decode(String.self, forKey: .creator)
        self.type = try c.decode(MediaType.self, forKey: .type)
        self.genre = try c.decode(String.self, forKey: .genre)
        self.synopsis = try c.decode(String.self, forKey: .synopsis)
        self.aiTools = try c.decode([String].self, forKey: .aiTools)
        self.commercialScore = try c.decode(Int.self, forKey: .commercialScore)
        self.price = try c.decode(Double.self, forKey: .price)
        self.releaseYear = try c.decodeIfPresent(Int.self, forKey: .releaseYear) ?? 2026
        self.length = try c.decode(Int.self, forKey: .length)
        self.maturity = try c.decodeIfPresent(String.self, forKey: .maturity) ?? "13+"
        self.purchases = try c.decodeIfPresent(Int.self, forKey: .purchases) ?? 0
        self.trending = try c.decodeIfPresent(Int.self, forKey: .trending) ?? 0
        self.addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? .now
        self.coverImageData = try c.decodeIfPresent(Data.self, forKey: .coverImageData)
        self.coverAssetName = try c.decodeIfPresent(String.self, forKey: .coverAssetName)
        self.mediaFileName = try c.decodeIfPresent(String.self, forKey: .mediaFileName)
        self.isEditorOriginal = try c.decodeIfPresent(Bool.self, forKey: .isEditorOriginal) ?? false
        self.localMediaFileName = try c.decodeIfPresent(String.self, forKey: .localMediaFileName)
        self.manuscriptText = try c.decodeIfPresent(String.self, forKey: .manuscriptText)
        self.coverHasTitle = try c.decodeIfPresent(Bool.self, forKey: .coverHasTitle) ?? false
        self.screenplayScenes = try c.decodeIfPresent([String].self, forKey: .screenplayScenes) ?? []
        self.sceneDurations = try c.decodeIfPresent([Int].self, forKey: .sceneDurations) ?? []
        self.targetMinutes = try c.decodeIfPresent(Int.self, forKey: .targetMinutes) ?? 0
        self.sceneVideoURLs = try c.decodeIfPresent([String].self, forKey: .sceneVideoURLs) ?? []
    }

    var priceLabel: String { String(format: "$%.2f", price) }
    var lengthLabel: String { type.lengthNoun(length) }
    var scoreLabel: String { "\(commercialScore)/100" }
    /// Per-item display label that's accurate for what the buyer's actually
    /// getting: a single music track shows "Song", a multi-track release
    /// shows "Album". Films and novels are unambiguous.
    var categoryLabel: String {
        switch type {
        case .music:  return length <= 1 ? "Song" : "Album"
        case .novel:  return "Novel"
        case .movie:  return "Film"
        }
    }

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
    return hash & Int.max   // abs(Int.min) traps; mask keeps it non-negative
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
