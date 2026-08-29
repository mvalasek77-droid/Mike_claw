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

    /// Real announced 2026–2027 slate. Titles + release dates from
    /// public studio schedules; tracking estimates + posters are
    /// baseline placeholders that get overwritten as soon as the
    /// TMDB / backend providers return live data. Emoji posters are
    /// last-resort fallback — real posters load from
    /// image.tmdb.org whenever the movie has a `posterURL`.
    ///
    /// Dates are relative windows anchored to the release calendar
    /// as of app compile-time. Once the TMDB provider is on, the
    /// live catalog supersedes this seed within 6 hours.
    static func builtInSeed() -> [Movie] {
        // Anchor a fixed reference date so relative windows don't drift
        // as this code sits in the binary. Users on live TMDB won't see
        // these anyway.
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.dateFormat = "yyyy-MM-dd"
        func date(_ s: String) -> Date { fmt.date(from: s) ?? Date() }

        let addedAt = Date().addingTimeInterval(-10 * 86400)
        return [
            .init(id: "m_avatar_fireash", title: "Avatar: Fire and Ash",
                  studio: "20th Century / Disney",
                  releaseDate: date("2025-12-19"), posterEmoji: "🔥",
                  tagline: "The war for Pandora burns on.",
                  consensusOpeningMillions: 145, impliedVolPct: 25,
                  genre: "Sci-Fi", addedAt: addedAt),
            .init(id: "m_zootopia2", title: "Zootopia 2",
                  studio: "Walt Disney Animation",
                  releaseDate: date("2025-11-26"), posterEmoji: "🐰",
                  tagline: "Judy and Nick are back on the case.",
                  consensusOpeningMillions: 60, impliedVolPct: 22,
                  genre: "Animation", addedAt: addedAt),
            .init(id: "m_wicked2", title: "Wicked: For Good",
                  studio: "Universal",
                  releaseDate: date("2025-11-21"), posterEmoji: "💚",
                  tagline: "The story ends where the story began.",
                  consensusOpeningMillions: 95, impliedVolPct: 24,
                  genre: "Musical", addedAt: addedAt),
            .init(id: "m_avengers_doomsday", title: "Avengers: Doomsday",
                  studio: "Marvel Studios",
                  releaseDate: date("2026-05-01"), posterEmoji: "⚡️",
                  tagline: "Doom always wins.",
                  consensusOpeningMillions: 180, impliedVolPct: 20,
                  genre: "Superhero", addedAt: addedAt),
            .init(id: "m_toystory5", title: "Toy Story 5",
                  studio: "Pixar",
                  releaseDate: date("2026-06-19"), posterEmoji: "🤠",
                  tagline: "The gang plays on.",
                  consensusOpeningMillions: 105, impliedVolPct: 22,
                  genre: "Animation", addedAt: addedAt),
            .init(id: "m_iceage6", title: "Ice Age: Boiling Point",
                  studio: "20th Century / Disney",
                  releaseDate: date("2026-07-24"), posterEmoji: "🦣",
                  tagline: "Sid, Manny and Diego face a hotter world.",
                  consensusOpeningMillions: 42, impliedVolPct: 28,
                  genre: "Animation", addedAt: addedAt),
            .init(id: "m_masters_universe", title: "Masters of the Universe",
                  studio: "Amazon MGM",
                  releaseDate: date("2026-06-05"), posterEmoji: "⚔️",
                  tagline: "Eternia rises.",
                  consensusOpeningMillions: 34, impliedVolPct: 40,
                  genre: "Action", addedAt: addedAt),
            .init(id: "m_super_mario_gala", title: "The Super Mario Galaxy Movie",
                  studio: "Illumination / Nintendo",
                  releaseDate: date("2026-04-03"), posterEmoji: "🍄",
                  tagline: "Mama mia, again.",
                  consensusOpeningMillions: 128, impliedVolPct: 22,
                  genre: "Animation", addedAt: addedAt),
            .init(id: "m_project_hail_mary", title: "Project Hail Mary",
                  studio: "Amazon MGM",
                  releaseDate: date("2026-03-20"), posterEmoji: "🚀",
                  tagline: "One man. The last hope for Earth.",
                  consensusOpeningMillions: 38, impliedVolPct: 35,
                  genre: "Sci-Fi", addedAt: addedAt),
            .init(id: "m_dune3", title: "Dune: Part Three",
                  studio: "Warner Bros. / Legendary",
                  releaseDate: date("2026-12-18"), posterEmoji: "🏜️",
                  tagline: "The desert dreams a new emperor.",
                  consensusOpeningMillions: 88, impliedVolPct: 26,
                  genre: "Sci-Fi", addedAt: addedAt),
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
        guard let url = comps.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, resp) = try await session.data(for: request)
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

    /// Legacy single-provider path. Prefer `Config.compositeProvider`.
    static var preferredProvider: MovieDataProvider { compositeProvider }
}
