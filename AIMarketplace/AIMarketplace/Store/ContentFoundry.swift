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
