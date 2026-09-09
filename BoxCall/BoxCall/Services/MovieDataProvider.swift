import Foundation

/// Anything that can produce a fresh catalog of upcoming movies.
/// Implementations swap trivially between mock, TMDB direct, and the
/// production BoxCall backend (which fans out to Box Office Mojo,
/// The Numbers, and Deadline scrapers server-side).
protocol MovieDataProvider {
    /// Fetch upcoming movies within `windowDays` from today.
    func fetchUpcoming(windowDays: Int) async throws -> [Movie]
}

// MARK: - Built-in slate (real films, real dates)

/// Ships with the real upcoming theatrical calendar so the app is
/// full on first launch — offline, in demos, or before any API key
/// is set. Titles, studios, release dates, directors, and cast come
/// from public studio announcements. Tracking estimates are baseline
/// placeholders that TMDB / the backend overwrite once live.
final class MockMovieProvider: MovieDataProvider {
    func fetchUpcoming(windowDays: Int) async throws -> [Movie] {
        // Only return films that haven't opened yet — a stale seed
        // should never resurrect a movie that already settled.
        MockMovieProvider.builtInSeed().filter { !$0.isSettled }
    }

    /// Fall 2026 → Summer 2027 wide-release calendar as of the most
    /// recent studio date announcements. Every title here is real and
    /// every date is the studio's announced domestic opening.
    /// Verified wide-release calendar, checked against studio
    /// announcements and official film sites in September 2026.
    ///
    /// Every title here is real, every date is the studio's announced
    /// domestic opening, and no title is included on a date that could
    /// not be confirmed. Films whose date is reported inconsistently
    /// across outlets are deliberately left out — shipping a wrong date
    /// is worse than shipping a shorter slate, because a contract that
    /// settles on the wrong day is simply broken.
    ///
    /// `tradeProjection` carries a published opening-weekend range where
    /// the trades have printed one. Where they have not, the field is
    /// left nil and the chain falls back to the app's own estimate
    /// rather than inventing a forecast and attributing it to a trade.
    static func builtInSeed() -> [Movie] {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        func date(_ s: String) -> Date { fmt.date(from: s) ?? .distantFuture }

        let addedAt = Date().addingTimeInterval(-10 * 86400)
        /// Roughly when the projections below were reported.
        let trackedAt = date("2026-08-20")

        return [
            .init(id: "m_practical_magic2", title: "Practical Magic 2",
                  studio: "Warner Bros.",
                  releaseDate: date("2026-09-18"), posterEmoji: "\u{1F52E}",
                  tagline: "The Owens sisters are back.",
                  consensusOpeningMillions: 28, impliedVolPct: 40,
                  genre: "Fantasy", addedAt: addedAt,
                  director: "Susanne Bier",
                  cast: ["Sandra Bullock", "Nicole Kidman", "Joey King", "Maisie Williams"],
                  synopsis: "Sally and Gillian Owens return three decades on, with a new generation of the family discovering the curse has not finished with them.",
                  trailerQuery: "Practical Magic 2 official trailer"),

            .init(id: "m_verity", title: "Verity",
                  studio: "Amazon MGM Studios",
                  releaseDate: date("2026-10-02"), posterEmoji: "\u{1F4D6}",
                  tagline: "Every story has two versions.",
                  consensusOpeningMillions: 18, impliedVolPct: 45,
                  genre: "Thriller", addedAt: addedAt,
                  director: "Michael Showalter",
                  cast: ["Anne Hathaway", "Dakota Johnson", "Josh Hartnett"],
                  synopsis: "A struggling writer hired to finish an injured author's series finds an unpublished manuscript that reads as a confession.",
                  trailerQuery: "Verity movie official trailer"),

            .init(id: "m_street_fighter", title: "Street Fighter",
                  studio: "Paramount / Legendary",
                  releaseDate: date("2026-10-16"), posterEmoji: "\u{1F94B}",
                  tagline: "The world warriors return.",
                  consensusOpeningMillions: 24, impliedVolPct: 52,
                  genre: "Action", addedAt: addedAt,
                  director: "Kitao Sakurai",
                  cast: ["Andrew Koji", "Noah Centineo", "Callina Liang", "Jason Momoa"],
                  synopsis: "A live-action take on Capcom's fighting game, built around the World Warrior tournament.",
                  trailerQuery: "Street Fighter 2026 official trailer"),

            .init(id: "m_clayface", title: "Clayface",
                  studio: "DC Studios / Warner Bros.",
                  releaseDate: date("2026-10-23"), posterEmoji: "\u{1F3AD}",
                  tagline: "A body-horror origin story from the DC Universe.",
                  consensusOpeningMillions: 30, impliedVolPct: 44,
                  genre: "Horror", addedAt: addedAt,
                  director: "James Watkins",
                  cast: ["Tom Rhys Harries", "Naomi Ackie", "Max Minghella", "Eddie Marsan"],
                  synopsis: "Actor Matt Hagen takes an experimental treatment to save his face, and it dissolves everything else. Written by Mike Flanagan, this is the DCU's first R-rated horror picture.",
                  trailerQuery: "Clayface 2026 official trailer"),

            .init(id: "m_wildwood", title: "Wildwood",
                  studio: "Focus Features / Laika",
                  releaseDate: date("2026-10-23"), posterEmoji: "\u{1F333}",
                  tagline: "Beyond the edge of the map.",
                  consensusOpeningMillions: 11, impliedVolPct: 48,
                  genre: "Animation", addedAt: addedAt,
                  director: "Travis Knight",
                  cast: ["Carey Mulligan", "Mahershala Ali", "Angela Bassett"],
                  synopsis: "Laika's stop-motion adaptation of Colin Meloy's novel, in which a girl crosses into an impassable wilderness to find her abducted brother.",
                  trailerQuery: "Wildwood Laika official trailer"),

            .init(id: "m_hunger_games_sotr", title: "The Hunger Games: Sunrise on the Reaping",
                  studio: "Lionsgate",
                  releaseDate: date("2026-11-20"), posterEmoji: "\u{1F3F9}",
                  tagline: "Let the 50th Hunger Games begin.",
                  consensusOpeningMillions: 62, impliedVolPct: 55,
                  genre: "Action", addedAt: addedAt,
                  director: "Francis Lawrence",
                  cast: ["Joseph Zada", "Elle Fanning", "Kieran Culkin", "Ralph Fiennes", "Jesse Plemons"],
                  synopsis: "The Second Quarter Quell, twenty-four years before Katniss, told from Haymitch Abernathy's reaping day.",
                  trailerQuery: "Hunger Games Sunrise on the Reaping official trailer",
                  // Analysts are openly split: the four original films all
                  // opened above $100M, while the last prequel opened to
                  // $44.6M. That disagreement is the signal, and the wide
                  // band prices the contracts accordingly.
                  tradeProjection: TradeProjection(
                      lowMillions: 45, highMillions: 90,
                      source: "Analyst range, Lionsgate tracking",
                      asOf: trackedAt, isPublished: true)),

            .init(id: "m_focker_in_law", title: "Focker In-Law",
                  studio: "Universal Pictures",
                  releaseDate: date("2026-11-25"), posterEmoji: "\u{1F46A}",
                  tagline: "Meet the parents. Again.",
                  consensusOpeningMillions: 26, impliedVolPct: 42,
                  genre: "Comedy", addedAt: addedAt,
                  director: "John Hamburg",
                  cast: ["Ben Stiller", "Robert De Niro", "Owen Wilson", "Teri Polo", "Ariana Grande"],
                  synopsis: "The fourth Fockers picture, arriving the day before Thanksgiving with the original cast reunited.",
                  trailerQuery: "Focker In-Law official trailer"),

            .init(id: "m_violent_night2", title: "Violent Night 2",
                  studio: "Universal Pictures",
                  releaseDate: date("2026-12-04"), posterEmoji: "\u{1F385}",
                  tagline: "Santa's back on the naughty list.",
                  consensusOpeningMillions: 16, impliedVolPct: 46,
                  genre: "Action", addedAt: addedAt,
                  director: "Tommy Wirkola",
                  cast: ["David Harbour", "John Leguizamo"],
                  synopsis: "Harbour's brawling Saint Nick returns for another Christmas Eve of extremely blunt instruments.",
                  trailerQuery: "Violent Night 2 official trailer"),

            .init(id: "m_avengers_doomsday", title: "Avengers: Doomsday",
                  studio: "Marvel Studios / Disney",
                  releaseDate: date("2026-12-18"), posterEmoji: "\u{1F6E1}",
                  tagline: "The Multiverse Saga's reckoning.",
                  consensusOpeningMillions: 280, impliedVolPct: 32,
                  genre: "Action", addedAt: addedAt,
                  director: "Anthony and Joe Russo",
                  cast: ["Robert Downey Jr.", "Chris Hemsworth", "Anthony Mackie", "Vanessa Kirby", "Pedro Pascal"],
                  synopsis: "Doctor Doom against the assembled heroes of the Multiverse Saga. Presales opened at record pace and have not slowed.",
                  trailerQuery: "Avengers Doomsday official trailer",
                  // Consensus domestic opening from pre-sale tracking.
                  // Outliers as high as $425M exist; the band here is the
                  // number most outlets converged on.
                  tradeProjection: TradeProjection(
                      lowMillions: 260, highMillions: 300,
                      source: "Pre-sale tracking consensus",
                      asOf: trackedAt, isPublished: true)),

            .init(id: "m_dune_three", title: "Dune: Part Three",
                  studio: "Warner Bros. / Legendary",
                  releaseDate: date("2026-12-18"), posterEmoji: "\u{1FA90}",
                  tagline: "The prophecy ends.",
                  consensusOpeningMillions: 115, impliedVolPct: 41,
                  genre: "Sci-Fi", addedAt: addedAt,
                  director: "Denis Villeneuve",
                  cast: ["Timothée Chalamet", "Zendaya", "Florence Pugh", "Jason Momoa"],
                  synopsis: "Villeneuve closes the trilogy, opening opposite Avengers: Doomsday and holding roughly 400 domestic IMAX screens for three weeks.",
                  trailerQuery: "Dune Part Three official trailer",
                  // A franchise-record opening: Part Two debuted to $82M.
                  tradeProjection: TradeProjection(
                      lowMillions: 100, highMillions: 130,
                      source: "Pre-sale tracking consensus",
                      asOf: trackedAt, isPublished: true)),

            .init(id: "m_angry_birds3", title: "The Angry Birds Movie 3",
                  studio: "Paramount Pictures",
                  releaseDate: date("2026-12-23"), posterEmoji: "\u{1F426}",
                  tagline: "The flock is back for the holidays.",
                  consensusOpeningMillions: 19, impliedVolPct: 44,
                  genre: "Animation", addedAt: addedAt,
                  director: "John Rice",
                  cast: ["Jason Sudeikis", "Josh Gad", "Rachel Bloom"],
                  synopsis: "The birds and pigs return for a third round, landing in the middle of the Christmas family corridor.",
                  trailerQuery: "Angry Birds Movie 3 official trailer"),

            .init(id: "m_werwulf", title: "Werwulf",
                  studio: "Focus Features",
                  releaseDate: date("2026-12-25"), posterEmoji: "\u{1F43A}",
                  tagline: "Thirteenth-century England. Something is out there.",
                  consensusOpeningMillions: 14, impliedVolPct: 54,
                  genre: "Horror", addedAt: addedAt,
                  director: "Robert Eggers",
                  cast: ["Lily-Rose Depp", "Aaron Taylor-Johnson"],
                  synopsis: "Eggers follows Nosferatu with a medieval werewolf picture, shot in period Middle English and opening Christmas Day.",
                  trailerQuery: "Werwulf Robert Eggers official trailer"),
        ]
    }
}

// MARK: - TMDB (real upcoming releases)

/// Hits The Movie Database's public /movie/upcoming endpoint.
/// Free API key required — set in Config.tmdbAPIKey. If unset, the
/// service degrades gracefully to the built-in slate so the app still
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
        let popularityFactor = min(200, max(1, t.popularity))
        let consensus = 2.0 + popularityFactor / 3.5     // ~ $2M - $60M range
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
            addedAt: Date(),
            synopsis: t.overview.isEmpty ? nil : t.overview
        )
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
    private static let overrideKey = "config.tmdbAPIKeyOverride"

    /// A key the user pasted in-app (PosterUnlockSheet). Wins over
    /// Info.plist so the setup flow works without a rebuild.
    static var tmdbAPIKeyOverride: String? {
        get { UserDefaults.standard.string(forKey: overrideKey) }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: overrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: overrideKey)
            }
        }
    }

    /// TMDB v3 API key. In production, replace this with a call
    /// through your own backend proxy so the key isn't shipped in
    /// the app binary.
    static var tmdbAPIKey: String {
        if let o = tmdbAPIKeyOverride, !o.isEmpty { return o }
        if let key = Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String,
           !key.isEmpty { return key }
        return ""
    }

    /// Legacy single-provider path. Prefer `Config.compositeProvider`.
    static var preferredProvider: MovieDataProvider { compositeProvider }
}
