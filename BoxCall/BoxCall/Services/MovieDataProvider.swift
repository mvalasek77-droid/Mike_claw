import Foundation

/// Anything that can produce a fresh catalog of upcoming movies.
/// Implementations swap trivially between mock, TMDB direct, and the
/// production BoxCall backend (which fans out to Box Office Mojo,
/// The Numbers, and Deadline scrapers server-side).
protocol MovieDataProvider {
    /// Fetch upcoming movies within `windowDays` from today.
    func fetchUpcoming(windowDays: Int) async throws -> [Movie]
}

// MARK: - Mock (built-in seed)

/// Ships with a hand-curated slate of eight fictional titles so the
/// app is usable offline, in demos, or before any API key is set.
final class MockMovieProvider: MovieDataProvider {
    func fetchUpcoming(windowDays: Int) async throws -> [Movie] {
        MockMovieProvider.builtInSeed()
    }

    static func builtInSeed() -> [Movie] {
        let today = Calendar.current.startOfDay(for: Date())
        func d(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: n, to: today)! }
        let addedAt = Date().addingTimeInterval(-10 * 86400)  // not "NEW"
        return [
            .init(id: "m_neon", title: "Neon Requiem", studio: "A24",
                  releaseDate: d(5), posterEmoji: "🌃", tagline: "A cyberpunk grief opera.",
                  consensusOpeningMillions: 12, impliedVolPct: 55, genre: "Sci-Fi", addedAt: addedAt),
            .init(id: "m_glacier", title: "Glacier", studio: "Universal",
                  releaseDate: d(9), posterEmoji: "🏔️", tagline: "The mountain will not forgive.",
                  consensusOpeningMillions: 34, impliedVolPct: 32, genre: "Thriller", addedAt: addedAt),
            .init(id: "m_starmap", title: "Starmap 3: Ascension", studio: "Marvel Studios",
                  releaseDate: d(14), posterEmoji: "🚀", tagline: "Every hero has a horizon.",
                  consensusOpeningMillions: 168, impliedVolPct: 22, genre: "Superhero", addedAt: addedAt),
            .init(id: "m_prowl", title: "Prowl", studio: "Blumhouse",
                  releaseDate: d(18), posterEmoji: "🐺", tagline: "Something is hunting the hunters.",
                  consensusOpeningMillions: 21, impliedVolPct: 48, genre: "Horror", addedAt: addedAt),
            .init(id: "m_paperhouse", title: "The Paper House", studio: "Searchlight",
                  releaseDate: d(23), posterEmoji: "📜", tagline: "A love story, folded once.",
                  consensusOpeningMillions: 6, impliedVolPct: 65, genre: "Drama", addedAt: addedAt),
            .init(id: "m_atlas", title: "Atlas & Sons", studio: "Warner Bros.",
                  releaseDate: d(30), posterEmoji: "⚔️", tagline: "The empire runs in the family.",
                  consensusOpeningMillions: 58, impliedVolPct: 28, genre: "Action", addedAt: addedAt),
            .init(id: "m_karaoke", title: "Karaoke Night", studio: "Sony Pictures Classics",
                  releaseDate: d(37), posterEmoji: "🎤", tagline: "Everyone's the star. Nobody remembers.",
                  consensusOpeningMillions: 4, impliedVolPct: 70, genre: "Comedy", addedAt: addedAt),
            .init(id: "m_deepblue", title: "Deep Blue Country", studio: "Netflix (Theatrical)",
                  releaseDate: d(44), posterEmoji: "🌊", tagline: "The tide brought something back.",
                  consensusOpeningMillions: 9, impliedVolPct: 60, genre: "Mystery", addedAt: addedAt)
        ]
    }
}

// MARK: - TMDB (real upcoming releases)

/// Hits The Movie Database's public /movie/upcoming endpoint.
/// Free API key required — set in Config.tmdbAPIKey. If unset, the
/// service degrades gracefully to the mock provider so the app still
/// runs. In production, calls should route through your own backend
/// (boxcall.com/api/upcoming) that proxies TMDB, layers on tracking
/// numbers from The Numbers / Deadline, and normalizes the schema.
final class TMDBMovieProvider: MovieDataProvider {
    private let apiKey: String
    private let session: URLSession
    private let base = URL(string: "https://api.themoviedb.org/3")!
    private let imageBase = "https://image.tmdb.org/t/p/w500"

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func fetchUpcoming(windowDays: Int) async throws -> [Movie] {
        var comps = URLComponents(url: base.appendingPathComponent("movie/upcoming"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "api_key", value: apiKey),
            .init(name: "language", value: "en-US"),
            .init(name: "region", value: "US"),
            .init(name: "page", value: "1")
        ]
        let (data, resp) = try await session.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        decoder.dateDecodingStrategy = .formatted(dateFormatter)

        let envelope = try decoder.decode(TMDBUpcomingEnvelope.self, from: data)

        let cutoff = Date().addingTimeInterval(Double(windowDays) * 86400)
        return envelope.results
            .filter { $0.releaseDate <= cutoff && $0.releaseDate >= Date().addingTimeInterval(-2 * 86400) }
            .prefix(20)
            .map { self.mapToMovie($0) }
    }

    private func mapToMovie(_ t: TMDBMovie) -> Movie {
        // Rough algorithmic consensus + IV — in production, replace with
        // pre-release tracking pulled from Deadline / The Numbers.
        let daysOut = max(1, Calendar.current.dateComponents([.day],
                          from: Date(), to: t.releaseDate).day ?? 30)
        // Popularity is TMDB's proprietary trending score; loose proxy for anticipation.
        let popularityFactor = min(200, max(1, t.popularity))
        let consensus = 2.0 + popularityFactor / 3.5     // ~ $2M - $60M range
        // Independent films / low-popularity get higher IV.
        let iv = max(20.0, 80.0 - popularityFactor * 0.25)

        return Movie(
            id: "tmdb_\(t.id)",
            title: t.title,
            studio: t.productionCompanies?.first?.name ?? "—",
            releaseDate: t.releaseDate,
            posterEmoji: TMDBMovieProvider.emojiForGenre(t.primaryGenre),
            posterURL: t.posterPath.map { imageBase + $0 },
            tagline: t.overview.split(separator: ".").first.map { String($0) + "." } ?? t.title,
            consensusOpeningMillions: consensus.rounded(),
            impliedVolPct: iv.rounded(),
            genre: t.primaryGenre ?? "—",
            addedAt: Date()
        )
        _ = daysOut
    }

    static func emojiForGenre(_ g: String?) -> String {
        switch (g ?? "").lowercased() {
        case let s where s.contains("horror"):      return "🕷️"
        case let s where s.contains("science"):     return "🚀"
        case let s where s.contains("action"):      return "💥"
        case let s where s.contains("comedy"):      return "🎭"
        case let s where s.contains("drama"):       return "🎬"
        case let s where s.contains("thriller"):    return "🎯"
        case let s where s.contains("animation"):   return "🎨"
        case let s where s.contains("romance"):     return "💌"
        case let s where s.contains("family"):      return "🧸"
        case let s where s.contains("documentary"): return "📽️"
        case let s where s.contains("music"):       return "🎤"
        case let s where s.contains("mystery"):     return "🕵️"
        default:                                    return "🎞️"
        }
    }
}

// MARK: - TMDB response models

private struct TMDBUpcomingEnvelope: Decodable {
    let results: [TMDBMovie]
}

private struct TMDBMovie: Decodable {
    let id: Int
    let title: String
    let overview: String
    let releaseDate: Date
    let posterPath: String?
    let popularity: Double
    let genreIds: [Int]?
    let productionCompanies: [TMDBCompany]?

    private static let genreLookup: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance",
        878: "Science Fiction", 10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western"
    ]

    var primaryGenre: String? {
        guard let first = genreIds?.first else { return nil }
        return Self.genreLookup[first]
    }

    enum CodingKeys: String, CodingKey {
        case id, title, overview, popularity
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case genreIds = "genre_ids"
        case productionCompanies = "production_companies"
    }
}

private struct TMDBCompany: Decodable {
    let name: String
}

// MARK: - Config

enum Config {
    /// TMDB v3 API key. In production, replace this with a call
    /// through your own backend proxy so the key isn't shipped in
    /// the app binary.
    static var tmdbAPIKey: String {
        if let key = Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String,
           !key.isEmpty { return key }
        return ""
    }

    static var preferredProvider: MovieDataProvider {
        if !tmdbAPIKey.isEmpty {
            return TMDBMovieProvider(apiKey: tmdbAPIKey)
        }
        return MockMovieProvider()
    }
}
