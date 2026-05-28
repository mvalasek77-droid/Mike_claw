import Foundation

/// The AI Editor's own production house. When creators aren't filling a
/// category, the Editor generates polished, high-quality "Originals" so the
/// store never looks empty. Generation is fully deterministic (seeded), so the
/// same Originals appear every launch and their entitlements stay stable.
///
/// Originals are clearly attributed to ``ContentFoundry/studioName`` and flagged
/// with `isEditorOriginal`, never passed off as creator uploads.
enum ContentFoundry {
    static let studioName = "AI Marketplace Studios"
    /// Target number of titles per media type before the Editor stops filling.
    static let targetPerType = 9

    /// Generates Originals to bring each media type up to `targetPerType`,
    /// given what creators (and the seed catalogue) already supply.
    static func fillGaps(in catalog: [MediaItem]) -> [MediaItem] {
        var originals: [MediaItem] = []
        for type in MediaType.allCases {
            let have = catalog.filter { $0.type == type }.count
            let need = max(0, targetPerType - have)
            for index in 0..<need {
                originals.append(make(type: type, index: index))
            }
        }
        return originals
    }

    /// Titles attributed to a specific AI partner when it's activated, so the
    /// model immediately "adds media" (and starts earning). Deterministic.
    static func partnerTitles(for model: String, count: Int = 2) -> [MediaItem] {
        guard let type = AIToolCatalog.type(for: model) else { return [] }
        return (0..<count).map { i in
            let key = "partner-\(model)-\(i)"
            let title = title(for: type, key: key)
            let slug = SampleData.slugify(title)
            return MediaItem(
                id: deterministicID(key + title),
                title: title,
                creator: model,
                type: type,
                genre: pick(genres(for: type), key + "g"),
                synopsis: synopsis(for: type, title: title, genre: pick(genres(for: type), key + "g"), key: key),
                aiTools: [model],
                commercialScore: 88 + (stableHash(key + "s") % 10),
                price: pick([3.99, 4.99, 5.99, 6.99, 7.99], key + "p"),
                length: length(for: type, key: key),
                purchases: 60 + (stableHash(key + "b") % 500),
                trending: 60 + (stableHash(key + "t") % 30),
                addedAt: Date().addingTimeInterval(-Double(stableHash(key + "a") % 900_000)),
                coverAssetName: slug,
                mediaFileName: type == .novel ? nil : slug,
                isEditorOriginal: true
            )
        }
    }

    /// A brand-new, original Editor work in a specific (demanded) genre. Unique
    /// id each call so the catalogue keeps growing as demand is learned.
    static func freshDrop(type: MediaType, genre: String, seed: Int) -> MediaItem {
        let key = "drop-\(seed)-\(type.rawValue)-\(genre)"
        let title = title(for: type, key: key)
        let slug = SampleData.slugify(title)
        return MediaItem(
            id: UUID(),
            title: title,
            creator: studioName,
            type: type,
            genre: genre,
            synopsis: synopsis(for: type, title: title, genre: genre, key: key),
            aiTools: tools(for: type, key: key),
            commercialScore: 90 + (stableHash(key + "s") % 8),
            price: pick([4.99, 5.99, 6.99], key + "p"),
            length: length(for: type, key: key),
            purchases: 0,
            trending: 72,
            addedAt: Date(),
            coverAssetName: slug,
            mediaFileName: type == .novel ? nil : slug,
            isEditorOriginal: true
        )
    }

    /// A bespoke title produced by a model to fulfil a human commission.
    /// Attributed to the model, in the requested genre, at the agreed quality.
    static func commission(model: String, type: MediaType, genre: String, seed: Int, score: Int) -> MediaItem {
        let key = "commission-\(model)-\(seed)-\(genre)"
        let title = title(for: type, key: key)
        let slug = SampleData.slugify(title)
        return MediaItem(
            id: UUID(),
            title: title,
            creator: model,
            type: type,
            genre: genre,
            synopsis: synopsis(for: type, title: title, genre: genre, key: key),
            aiTools: [model],
            commercialScore: max(85, min(99, score)),
            price: 4.99,
            length: length(for: type, key: key),
            purchases: 0,
            trending: 70,
            addedAt: Date(),
            coverAssetName: slug,
            mediaFileName: type == .novel ? nil : slug,
            isEditorOriginal: true
        )
    }

    /// The three release layers the Scout always mixes across.
    enum ScoutLayer: String, CaseIterable { case commercial, experimental, niche }

    static let nicheGenres: [MediaType: [String]] = [
        .novel: ["Slipstream", "Solarpunk", "Cli-Fi", "Bizarro", "New Weird"],
        .music: ["Vaporwave", "Drone", "Hyperpop", "Field Recording", "Microtonal"],
        .movie: ["Avant-Garde", "Slow Cinema", "Mockumentary", "Anthology", "Arthouse"]
    ]

    static func layer(forGenre genre: String) -> ScoutLayer {
        if genre == "Experimental" { return .experimental }
        if MediaType.allCases.contains(where: { nicheGenres[$0]?.contains(genre) == true }) { return .niche }
        return .commercial
    }

    /// A Scout-sourced work in a given layer. `developing` items start below the
    /// 85% bar ("Coming Soon") and the Scout raises them over cycles until live.
    static func scoutPick(type: MediaType, layer: ScoutLayer, genre: String, developing: Bool, seed: Int) -> MediaItem {
        let key = "scout-\(seed)-\(type.rawValue)-\(layer.rawValue)"
        let model = pick(AIToolCatalog.suggestions(for: type), key + "model")
        let resolvedGenre: String
        switch layer {
        case .experimental: resolvedGenre = "Experimental"
        case .niche: resolvedGenre = pick(nicheGenres[type] ?? ["Niche"], key + "ng")
        case .commercial: resolvedGenre = genre
        }
        let title = layer == .experimental ? experimentalTitle(for: type, key: key) : title(for: type, key: key)
        let slug = SampleData.slugify(title) + "-\(abs(stableHash(key)) % 9999)"
        let target: Int
        switch layer {
        case .commercial: target = 95 + abs(stableHash(key + "s")) % 6
        case .experimental: target = 88 + abs(stableHash(key + "s")) % 8
        case .niche: target = 86 + abs(stableHash(key + "s")) % 8
        }
        let score = developing ? 62 + abs(stableHash(key + "d")) % 18 : min(100, target)
        return MediaItem(
            id: UUID(),
            title: title,
            creator: model,
            type: type,
            genre: resolvedGenre,
            synopsis: scoutSynopsis(for: type, layer: layer, genre: resolvedGenre, key: key),
            aiTools: [model],
            commercialScore: score,
            price: pick([4.99, 5.99, 6.99, 7.99], key + "p"),
            length: length(for: type, key: key),
            purchases: 0,
            trending: 84,
            addedAt: Date(),
            coverAssetName: slug,
            mediaFileName: type == .novel ? nil : slug,
            isEditorOriginal: true
        )
    }

    private static func experimentalTitle(for type: MediaType, key: String) -> String {
        let forms = ["Untitled (\(pick(nouns, key + "n")))", "\(pick(adjectives, key + "a")) // Études",
                     "Field Recording: \(pick(nouns, key + "n2"))", "No.\(abs(stableHash(key)) % 99) — \(pick(nouns, key + "n3"))"]
        return pick(forms, key + "f")
    }

    /// Formula-aware copy — encodes the proven patterns the Scout targets.
    private static func scoutSynopsis(for type: MediaType, layer: ScoutLayer, genre: String, key: String) -> String {
        let formula: String
        switch type {
        case .novel: formula = "a first-page hook, a propulsive three-act structure, escalating stakes, and an earned, resonant ending"
        case .music: formula = "a magnetic hook by 0:20, a tight verse-chorus build, a memorable drop, and replay-ready dynamics"
        case .movie: formula = "a cold-open hook, clear act breaks, plot-driven momentum, sharp comic timing where it counts, and a satisfying payoff"
        }
        let noun = type.title.lowercased()
        switch layer {
        case .commercial:
            return "A crowd-pleasing \(genre.lowercased()) \(noun) engineered to the proven commercial formula: \(formula). Built to sell."
        case .experimental:
            return "A daring, format-bending \(noun) testing what audiences will embrace next - keeping \(formula) where it matters, breaking the rest."
        case .niche:
            return "A \(genre.lowercased()) \(noun) for a passionate audience - honoring \(formula) while serving a specific taste superbly."
        }
    }

    // MARK: - Generation

    private static func make(type: MediaType, index: Int) -> MediaItem {
        let key = "\(type.rawValue)#\(index)"
        let title = title(for: type, key: key)
        let genre = pick(genres(for: type), key + "g")
        let tools = tools(for: type, key: key)
        let score = 90 + (stableHash(key + "score") % 8)            // 90–97: really high
        let price = pick([3.99, 4.99, 5.99, 6.99, 7.99, 9.99], key + "p")
        let length = length(for: type, key: key)
        let slug = SampleData.slugify(title)

        return MediaItem(
            id: deterministicID(key + title),
            title: title,
            creator: studioName,
            type: type,
            genre: genre,
            synopsis: synopsis(for: type, title: title, genre: genre, key: key),
            aiTools: tools,
            commercialScore: score,
            price: price,
            length: length,
            maturity: "13+",
            purchases: 40 + (stableHash(key + "buys") % 400),
            trending: 55 + (stableHash(key + "tr") % 35),
            addedAt: Date().addingTimeInterval(-Double(stableHash(key + "age") % 1_900_000)),
            coverAssetName: slug,
            mediaFileName: type == .novel ? nil : slug,
            isEditorOriginal: true
        )
    }

    // MARK: - Word banks

    private static func genres(for type: MediaType) -> [String] {
        switch type {
        case .novel: return ["Literary Fiction", "Science Fiction", "Fantasy", "Thriller", "Mystery", "Historical", "Speculative"]
        case .music: return ["Ambient", "Synthwave", "Neo-Classical", "Lo-Fi", "Electronic", "Cinematic", "Jazz"]
        case .movie: return ["Science Fiction", "Drama", "Thriller", "Animation", "Documentary", "Adventure"]
        }
    }

    static func defaultGenre(for type: MediaType) -> String { genres(for: type).first ?? "Original" }

    private static let adjectives = ["Silent", "Hidden", "Distant", "Gilded", "Hollow", "Northern", "Forgotten", "Glass", "Quiet", "Crimson", "Luminous", "Vanishing"]
    private static let nouns = ["Cartographer", "Lighthouse", "Inheritance", "Archive", "Equinox", "Cathedral", "Lantern", "Reckoning", "Wilderness", "Cipher", "Aurora", "Monsoon", "Halcyon", "Meridian", "Threshold", "Ember"]

    private static func title(for type: MediaType, key: String) -> String {
        let a = pick(adjectives, key + "a")
        let n = pick(nouns, key + "n")
        let n2 = pick(nouns, key + "n2")
        let patterns: [String]
        switch type {
        case .novel: patterns = ["The \(n) of \(n2)", "\(a) \(n)", "The Last \(n)", "\(n) & \(n2)"]
        case .music: patterns = ["\(a) \(n)", "\(n) // \(n2)", "Songs for the \(n)", "\(n) in \(a) Light"]
        case .movie: patterns = ["\(a) \(n)", "The \(n) Protocol", "\(n): \(a) Skies", "After the \(n)"]
        }
        return pick(patterns, key + "t")
    }

    private static func tools(for type: MediaType, key: String) -> [String] {
        let all = AIToolCatalog.suggestions(for: type)
        let first = pick(all, key + "tool1")
        let second = pick(all, key + "tool2")
        return first == second ? [first] : [first, second]
    }

    private static func length(for type: MediaType, key: String) -> Int {
        switch type {
        case .novel: return 220 + (stableHash(key + "len") % 200)
        case .music: return 8 + (stableHash(key + "len") % 7)
        case .movie: return 92 + (stableHash(key + "len") % 48)
        }
    }

    private static func synopsis(for type: MediaType, title: String, genre: String, key: String) -> String {
        let hooks = [
            "A debut that announces a singular new voice.",
            "Assured, immersive, and impossible to put down.",
            "The kind of work the AI Editor flags as ready for a wide audience.",
            "Crafted with restraint and a sharp emotional core."
        ]
        let hook = pick(hooks, key + "h")
        switch type {
        case .novel:
            return "A \(genre.lowercased()) novel that follows one unforgettable character across a single, decisive turning point — and the quiet aftershocks that ripple outward for years. \(hook)"
        case .music:
            return "A \(genre.lowercased()) record built around warm, deliberate production: patient arrangements, real dynamics, and hooks that reveal themselves on the second listen. \(hook)"
        case .movie:
            return "A \(genre.lowercased()) feature with confident pacing, striking composition, and a story that earns its ending. \(hook)"
        }
    }

    // MARK: - Deterministic helpers

    private static func pick<T>(_ array: [T], _ salt: String) -> T {
        let i = abs(stableHash(salt)) % max(array.count, 1)
        return array[i]
    }

    /// Stable UUID derived from a key, so generated Originals keep the same id
    /// (and therefore the same purchases/entitlements) across launches.
    static func deterministicID(_ key: String) -> UUID {
        let a = UInt64(bitPattern: Int64(stableHash(key)))
        let b = UInt64(bitPattern: Int64(stableHash(key + "::uuid")))
        let hex = String(format: "%016llx%016llx", a, b)
        let chars = Array(hex)
        func slice(_ lo: Int, _ hi: Int) -> String { String(chars[lo..<hi]) }
        let s = "\(slice(0,8))-\(slice(8,12))-\(slice(12,16))-\(slice(16,20))-\(slice(20,32))"
        return UUID(uuidString: s) ?? UUID()
    }
}
