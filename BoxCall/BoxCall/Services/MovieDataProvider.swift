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
    static func builtInSeed() -> [Movie] {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = TimeZone.current
        fmt.dateFormat = "yyyy-MM-dd"
        func date(_ s: String) -> Date { fmt.date(from: s) ?? .distantFuture }

        let addedAt = Date().addingTimeInterval(-10 * 86400)
        return [
            .init(id: "m_clayface", title: "Clayface",
                  studio: "DC Studios / Warner Bros.",
                  releaseDate: date("2026-09-11"), posterEmoji: "🎭",
                  tagline: "A body-horror origin story from the DC Universe.",
                  consensusOpeningMillions: 30, impliedVolPct: 42,
                  genre: "Horror", addedAt: addedAt,
                  director: "James Watkins",
                  cast: ["Tom Rhys Harries", "Naomi Ackie", "Max Minghella", "Eddie Marsan"],
                  synopsis: "Struggling actor Basil Karlo takes an experimental treatment to save his face — and it dissolves everything else. Written by Mike Flanagan, this is the DCU's first R-rated horror.",
                  trailerQuery: "Clayface 2026 official trailer"),
            .init(id: "m_practical_magic2", title: "Practical Magic 2",
                  studio: "Warner Bros.",
                  releaseDate: date("2026-09-18"), posterEmoji: "🔮",
                  tagline: "The Owens sisters return.",
                  consensusOpeningMillions: 28, impliedVolPct: 38,
                  genre: "Fantasy", addedAt: addedAt,
                  director: "Susanne Bier",
                  cast: ["Sandra Bullock", "Nicole Kidman", "Joey King", "Maisie Williams", "Lee Pace"],
                  synopsis: "Twenty-eight years later, Sally and Gillian Owens are back, with a new generation of Owens women — and the family curse — in tow.",
                  trailerQuery: "Practical Magic 2 official trailer"),
            .init(id: "m_resident_evil_2026", title: "Resident Evil",
                  studio: "Sony / Screen Gems",
                  releaseDate: date("2026-09-18"), posterEmoji: "🧟",
                  tagline: "From the director of Weapons.",
                  consensusOpeningMillions: 35, impliedVolPct: 40,
                  genre: "Horror", addedAt: addedAt,
                  director: "Zach Cregger",
                  cast: ["Austin Abrams", "Paul Walter Hauser", "Zach Cherry", "Kali Reis"],
                  synopsis: "A fresh, standalone take on the Capcom series from the Barbarian and Weapons director — a courier's routine delivery goes very wrong.",
                  trailerQuery: "Resident Evil 2026 Zach Cregger official trailer"),
            .init(id: "m_verity", title: "Verity",
                  studio: "Amazon MGM",
                  releaseDate: date("2026-10-02"), posterEmoji: "📖",
                  tagline: "Some manuscripts should stay hidden.",
                  consensusOpeningMillions: 24, impliedVolPct: 40,
                  genre: "Thriller", addedAt: addedAt,
                  director: "Michael Showalter",
                  cast: ["Anne Hathaway", "Dakota Johnson", "Josh Hartnett"],
                  synopsis: "A struggling writer hired to finish a bestselling author's series finds the author's unpublished autobiography — and its chilling confessions. From the Colleen Hoover novel.",
                  trailerQuery: "Verity movie official trailer"),
            .init(id: "m_social_reckoning", title: "The Social Reckoning",
                  studio: "Sony Pictures",
                  releaseDate: date("2026-10-09"), posterEmoji: "📱",
                  tagline: "The Social Network, sixteen years on.",
                  consensusOpeningMillions: 22, impliedVolPct: 38,
                  genre: "Drama", addedAt: addedAt,
                  director: "Aaron Sorkin",
                  cast: ["Jeremy Strong", "Mikey Madison", "Jeremy Allen White", "Bill Burr"],
                  synopsis: "Frances Haugen, a young Facebook engineer, teams with Wall Street Journal reporter Jeff Horwitz to expose what the company knew. Sorkin writes and directs.",
                  trailerQuery: "The Social Reckoning official trailer"),
            .init(id: "m_cat_in_the_hat", title: "The Cat in the Hat",
                  studio: "Warner Bros. Animation",
                  releaseDate: date("2026-11-06"), posterEmoji: "🎩",
                  tagline: "Dr. Seuss, animated, at last.",
                  consensusOpeningMillions: 40, impliedVolPct: 30,
                  genre: "Animation", addedAt: addedAt,
                  director: "Alessandro Carloni, Erica Rivinoja",
                  cast: ["Bill Hader", "Quinta Brunson", "Bowen Yang", "Xochitl Gomez", "Matt Berry"],
                  synopsis: "The Cat, an agent of the Institute for the Institution of Imagination, takes on a tough assignment: cheering up two kids who just moved to a new town.",
                  trailerQuery: "The Cat in the Hat 2026 official trailer"),
            .init(id: "m_hunger_games_sotr", title: "The Hunger Games: Sunrise on the Reaping",
                  studio: "Lionsgate",
                  releaseDate: date("2026-11-20"), posterEmoji: "🏹",
                  tagline: "Haymitch's Games.",
                  consensusOpeningMillions: 65, impliedVolPct: 26,
                  genre: "Sci-Fi", addedAt: addedAt,
                  director: "Francis Lawrence",
                  cast: ["Joseph Zada", "Whitney Peak", "Mckenna Grace", "Jesse Plemons", "Ralph Fiennes", "Kieran Culkin", "Elle Fanning"],
                  synopsis: "The 50th Hunger Games — the second Quarter Quell — as a sixteen-year-old Haymitch Abernathy is reaped from District 12 alongside twice the usual number of tributes.",
                  trailerQuery: "Hunger Games Sunrise on the Reaping official trailer"),
            .init(id: "m_focker_in_law", title: "Focker In-Law",
                  studio: "Universal",
                  releaseDate: date("2026-11-25"), posterEmoji: "🤝",
                  tagline: "The circle of trust gets bigger.",
                  consensusOpeningMillions: 35, impliedVolPct: 32,
                  genre: "Comedy", addedAt: addedAt,
                  director: "John Hamburg",
                  cast: ["Ben Stiller", "Robert De Niro", "Teri Polo", "Blythe Danner", "Ariana Grande"],
                  synopsis: "Greg Focker's kids are grown — and now it's his turn to interrogate a prospective in-law. Fourth film in the Meet the Parents series, Thanksgiving weekend.",
                  trailerQuery: "Focker In-Law official trailer"),
            .init(id: "m_narnia_nephew", title: "The Chronicles of Narnia: The Magician's Nephew",
                  studio: "Netflix (IMAX exclusive)",
                  releaseDate: date("2026-11-26"), posterEmoji: "🦁",
                  tagline: "Two-week IMAX run before streaming.",
                  consensusOpeningMillions: 18, impliedVolPct: 48,
                  genre: "Fantasy", addedAt: addedAt,
                  director: "Greta Gerwig",
                  cast: ["Emma Mackey", "Carey Mulligan", "Daniel Craig"],
                  synopsis: "Gerwig's Narnia begins at the beginning: Digory and Polly's rings, the dying world of Charn, the witch Jadis, and the song that makes a world.",
                  trailerQuery: "Narnia The Magician's Nephew Greta Gerwig official trailer"),
            .init(id: "m_jumanji3", title: "Jumanji 3",
                  studio: "Sony Pictures",
                  releaseDate: date("2026-12-11"), posterEmoji: "🥁",
                  tagline: "The game isn't over.",
                  consensusOpeningMillions: 50, impliedVolPct: 28,
                  genre: "Adventure", addedAt: addedAt,
                  director: "Jake Kasdan",
                  cast: ["Dwayne Johnson", "Kevin Hart", "Jack Black", "Karen Gillan", "Awkwafina"],
                  synopsis: "The avatars are back in the game, and this time the game has learned. The Rock, Hart, Black, and Gillan return for the third modern Jumanji.",
                  trailerQuery: "Jumanji 3 official trailer"),
            .init(id: "m_avengers_doomsday", title: "Avengers: Doomsday",
                  studio: "Marvel Studios",
                  releaseDate: date("2026-12-18"), posterEmoji: "⚡️",
                  tagline: "Opens head-to-head with Dune: Part Three.",
                  consensusOpeningMillions: 200, impliedVolPct: 20,
                  genre: "Superhero", addedAt: addedAt,
                  director: "Anthony & Joe Russo",
                  cast: ["Robert Downey Jr.", "Chris Hemsworth", "Pedro Pascal", "Vanessa Kirby", "Patrick Stewart", "Ian McKellen"],
                  synopsis: "Robert Downey Jr. returns as Doctor Doom. The Avengers, the Fantastic Four, and the X-Men are forced together against a man who says he is the only one who can save the multiverse.",
                  trailerQuery: "Avengers Doomsday official trailer"),
            .init(id: "m_dune3", title: "Dune: Part Three",
                  studio: "Warner Bros. / Legendary",
                  releaseDate: date("2026-12-18"), posterEmoji: "🏜️",
                  tagline: "Opens head-to-head with Avengers: Doomsday.",
                  consensusOpeningMillions: 85, impliedVolPct: 26,
                  genre: "Sci-Fi", addedAt: addedAt,
                  director: "Denis Villeneuve",
                  cast: ["Timothée Chalamet", "Zendaya", "Rebecca Ferguson", "Robert Pattinson", "Anya Taylor-Joy", "Jason Momoa"],
                  synopsis: "Adapting Dune Messiah — twelve years into Paul Atreides's reign as Emperor, a conspiracy among the Bene Gesserit, the Spacing Guild, and the Tleilaxu moves to end the jihad he unleashed.",
                  trailerQuery: "Dune Part Three official trailer"),
            .init(id: "m_iceage6", title: "Ice Age: Boiling Point",
                  studio: "20th Century / Disney",
                  releaseDate: date("2027-02-05"), posterEmoji: "🦣",
                  tagline: "The herd returns to theaters.",
                  consensusOpeningMillions: 45, impliedVolPct: 28,
                  genre: "Animation", addedAt: addedAt,
                  director: "20th Century Animation",
                  cast: ["Ray Romano", "John Leguizamo", "Denis Leary", "Queen Latifah", "Simon Pegg"],
                  synopsis: "Manny, Sid, and Diego navigate a world getting hotter by the minute in the sixth theatrical Ice Age — the first since 2016.",
                  trailerQuery: "Ice Age Boiling Point official trailer"),
            .init(id: "m_sonic4", title: "Sonic the Hedgehog 4",
                  studio: "Paramount",
                  releaseDate: date("2027-03-19"), posterEmoji: "💨",
                  tagline: "Gotta go fast. Again.",
                  consensusOpeningMillions: 58, impliedVolPct: 26,
                  genre: "Family", addedAt: addedAt,
                  director: "Jeff Fowler",
                  cast: ["Ben Schwartz", "Idris Elba", "Keanu Reeves", "Jim Carrey"],
                  synopsis: "Sonic, Tails, Knuckles, and Shadow face a new threat in the fourth film of Paramount's billion-dollar series.",
                  trailerQuery: "Sonic the Hedgehog 4 official trailer"),
            .init(id: "m_starfighter", title: "Star Wars: Starfighter",
                  studio: "Lucasfilm / Disney",
                  releaseDate: date("2027-05-28"), posterEmoji: "🚀",
                  tagline: "A new story, five years after The Rise of Skywalker.",
                  consensusOpeningMillions: 150, impliedVolPct: 24,
                  genre: "Sci-Fi", addedAt: addedAt,
                  director: "Shawn Levy",
                  cast: ["Ryan Gosling", "Mia Goth", "Matt Smith", "Flynn Gray", "Amy Adams"],
                  synopsis: "A standalone Star Wars adventure led by Ryan Gosling, directed by Shawn Levy, set after the Skywalker saga. Memorial Day weekend.",
                  trailerQuery: "Star Wars Starfighter official trailer"),
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
