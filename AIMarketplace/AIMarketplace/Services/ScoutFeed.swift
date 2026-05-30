import Foundation
import SwiftUI

/// Reference corpus that drives Scout's composition: 100ish canonical
/// bestsellers per medium, 10 masters per role (authors / producers /
/// directors), 15 blended recipes, current charts, and the latest model list.
/// Source of truth is `backend/src/scoutFeed.json`; the operator edits that
/// JSON and redeploys the Worker to grow the corpus.
///
/// Honest scope: this is *operator-curated patterns applied as composition
/// rules*, not real ML pattern-learning. Doing the latter would need copies
/// of the works themselves and significant training infrastructure.
struct ScoutFeed: Codable, Equatable {
    var version: String
    var models: [String]
    var bestsellers: BestsellersByMedium
    var masters: Masters
    var current: BestsellersByMedium
    var recipes: [Recipe]

    struct BestsellersByMedium: Codable, Equatable {
        var books: [Entry]
        var music: [Entry]
        var movies: [Entry]

        /// Compatible with `Current` blocks that omit pattern strings.
        struct Entry: Codable, Equatable {
            var t: String
            var c: String
            var y: Int
            var g: String
            var p: String?
        }
    }

    struct Masters: Codable, Equatable {
        var authors: [Master]
        var producers: [Master]
        var directors: [Master]
    }

    struct Master: Codable, Equatable {
        var n: String   // name
        var r: String   // role (author / producer / director)
        var patterns: [String]
    }

    struct Recipe: Codable, Equatable, Identifiable {
        var id: String
        var type: String        // "novel" / "music" / "movie" / "any"
        var genre: String
        var masters: [String]
        var sources: [String]
        var formula: String
        var experimental: Bool
        var weight: Double
    }

    /// Empty seed used as the offline fallback before the first fetch lands.
    static let empty = ScoutFeed(
        version: "offline",
        models: [],
        bestsellers: .init(books: [], music: [], movies: []),
        masters: .init(authors: [], producers: [], directors: []),
        current: .init(books: [], music: [], movies: []),
        recipes: []
    )
}

/// Fetches and caches the Scout feed.
///
/// Cache strategy: the JSON is persisted to Application Support and reused
/// across launches; the network is consulted at most every 12 hours, and
/// returns 304 Not Modified when the version hasn't changed (ETag).
@MainActor
final class ScoutFeedService: ObservableObject {
    @Published private(set) var feed: ScoutFeed = .empty
    @Published private(set) var lastFetched: Date?
    @Published private(set) var lastError: String?

    private var baseURL: String = ""
    private var sharedSecret: String = ""
    private var inFlight = false

    private static let cacheFileName = "scoutFeed.json"
    private static let etagDefaultsKey = "aimkt.scoutFeed.etag"
    private static let lastFetchedDefaultsKey = "aimkt.scoutFeed.lastFetched"
    private static let refreshInterval: TimeInterval = 12 * 60 * 60

    init() {
        loadCachedFeed()
        // Hand the catalogue any cached models immediately so the disclosure
        // step shows the latest list even before the network responds.
        AIToolCatalog.applyFeedModels(feed.models)
    }

    /// Wire the service to the same Worker the rest of the app uses.
    func configure(baseURL: String, sharedSecret: String) {
        self.baseURL = baseURL
        self.sharedSecret = sharedSecret
    }

    /// Fetch the feed if the cache is older than 12 hours (or `force == true`).
    /// Safe to call repeatedly; the in-flight guard collapses duplicate requests.
    func refreshIfDue(force: Bool = false) async {
        if !force, let when = lastFetched, Date().timeIntervalSince(when) < Self.refreshInterval {
            return
        }
        guard !inFlight else { return }
        guard !baseURL.isEmpty, !sharedSecret.isEmpty,
              let url = URL(string: "\(baseURL)/scout/feed") else { return }

        inFlight = true
        defer { inFlight = false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(sharedSecret)", forHTTPHeaderField: "Authorization")
        if let etag = UserDefaults.standard.string(forKey: Self.etagDefaultsKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { lastError = "No HTTP response"; return }

            switch http.statusCode {
            case 200:
                let decoded = try JSONDecoder().decode(ScoutFeed.self, from: data)
                self.feed = decoded
                self.lastFetched = Date()
                self.lastError = nil
                AIToolCatalog.applyFeedModels(decoded.models)
                persistCache(data: data, etag: http.value(forHTTPHeaderField: "ETag"))
                UserDefaults.standard.set(Date(), forKey: Self.lastFetchedDefaultsKey)
            case 304:
                self.lastFetched = Date()
                self.lastError = nil
                UserDefaults.standard.set(Date(), forKey: Self.lastFetchedDefaultsKey)
            default:
                self.lastError = "Scout feed HTTP \(http.statusCode)"
            }
        } catch {
            self.lastError = "Scout feed error: \(error.localizedDescription)"
        }
    }

    // MARK: - Composition helpers

    /// Pick a recipe for the given medium, with the "every 5th composition is
    /// experimental" rule applied by the caller's `cycleIndex`. Returns nil if
    /// the feed is empty.
    func pickRecipe(for type: String, cycleIndex: Int) -> ScoutFeed.Recipe? {
        let pool: [ScoutFeed.Recipe]
        if cycleIndex % 5 == 4 {
            pool = feed.recipes.filter { $0.experimental && ($0.type == type || $0.type == "any") }
        } else {
            pool = feed.recipes.filter { !$0.experimental && ($0.type == type || $0.type == "any") }
        }
        let candidates = pool.isEmpty ? feed.recipes.filter { $0.type == type || $0.type == "any" } : pool
        guard !candidates.isEmpty else { return nil }
        // Weighted pick via a deterministic hash of (version, type, cycleIndex)
        // so re-runs of the same cycle pick the same recipe for explainability.
        let totalWeight = candidates.reduce(0.0) { $0 + max($1.weight, 0.001) }
        var draw = abs(Double(deterministicHash("\(feed.version)|\(type)|\(cycleIndex)")) / Double(UInt32.max)) * totalWeight
        for r in candidates {
            draw -= max(r.weight, 0.001)
            if draw <= 0 { return r }
        }
        return candidates.last
    }

    /// One representative bestseller for the given medium (used for "in the
    /// spirit of …" copy). Prefers all-time list, falls back to current.
    func sampleBestseller(for type: String) -> ScoutFeed.BestsellersByMedium.Entry? {
        let book = bestsellerList(for: type)
        return book.randomElement() ?? currentList(for: type).randomElement()
    }

    private func bestsellerList(for type: String) -> [ScoutFeed.BestsellersByMedium.Entry] {
        switch type {
        case "novel": return feed.bestsellers.books
        case "music": return feed.bestsellers.music
        case "movie": return feed.bestsellers.movies
        default: return []
        }
    }

    private func currentList(for type: String) -> [ScoutFeed.BestsellersByMedium.Entry] {
        switch type {
        case "novel": return feed.current.books
        case "music": return feed.current.music
        case "movie": return feed.current.movies
        default: return []
        }
    }

    // MARK: - Cache

    private func loadCachedFeed() {
        guard let url = cacheURL(), let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode(ScoutFeed.self, from: data) {
            self.feed = decoded
        }
        if let when = UserDefaults.standard.object(forKey: Self.lastFetchedDefaultsKey) as? Date {
            self.lastFetched = when
        }
    }

    private func persistCache(data: Data, etag: String?) {
        if let url = cacheURL() {
            try? data.write(to: url, options: .atomic)
        }
        if let etag {
            UserDefaults.standard.set(etag, forKey: Self.etagDefaultsKey)
        }
    }

    private func cacheURL() -> URL? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent(Self.cacheFileName)
    }

    private func deterministicHash(_ s: String) -> UInt32 {
        // Simple FNV-1a 32-bit. Deterministic across launches.
        var h: UInt32 = 0x811c9dc5
        for byte in s.utf8 {
            h ^= UInt32(byte)
            h = h &* 0x01000193
        }
        return h
    }
}
