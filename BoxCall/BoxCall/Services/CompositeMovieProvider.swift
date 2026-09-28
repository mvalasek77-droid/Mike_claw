import Foundation

/// Merge multiple upcoming-movies providers into one deduped stream.
///
/// Later sources take priority when the same film appears twice; see
/// `Config.compositeProvider` for the order.
final class CompositeMovieProvider: MovieDataProvider {
    private let sources: [MovieDataProvider]
    init(_ sources: [MovieDataProvider]) { self.sources = sources }

    func fetchUpcoming(windowDays: Int) async throws -> [Movie] {
        var byKey: [String: Movie] = [:]
        var firstError: Error?

        for source in sources {
            do {
                let batch = try await source.fetchUpcoming(windowDays: windowDays)
                for m in batch {
                    let key = dedupKey(for: m)
                    // Later source wins the tie.
                    byKey[key] = m
                }
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if byKey.isEmpty, let error = firstError { throw error }
        return Array(byKey.values).sorted { $0.releaseDate < $1.releaseDate }
    }

    /// Same film, same key — even when sources disagree on the id or on
    /// a release date the studio has since moved.
    private func dedupKey(for m: Movie) -> String {
        Movie.titleKey(m.title)
    }
}

// MARK: - Published feed provider

/// Upcoming releases from the BoxCall data feed (`upcoming.json`), which
/// the BoxCall Data workflow rebuilds several times a day from Box Office
/// Mojo's and The Numbers' release calendars (and TMDB when a key is set).
/// This is how new films reach the app without an update.
final class PublishedCatalogProvider: MovieDataProvider {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = Config.dataAPIBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchUpcoming(windowDays: Int) async throws -> [Movie] {
        var request = URLRequest(url: baseURL.appendingPathComponent("upcoming.json"))
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        let today = Calendar.current.startOfDay(for: Date())
        let cutoff = today.addingTimeInterval(Double(windowDays) * 86_400)
        return feed.movies
            .compactMap { $0.movie() }
            .filter { $0.releaseDate >= today && $0.releaseDate <= cutoff }
    }

    private struct Feed: Decodable {
        let movies: [Entry]
    }

    private struct Entry: Decodable {
        let id: String
        let title: String
        let releaseDate: String
        let posterURL: String?
        let overview: String?
        let genre: String?
        let popularity: Double?
        let distributor: String?
        /// The pipeline's cold-start estimate for calendar films.
        let estimatedOpeningMillions: Double?

        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()

        func movie() -> Movie? {
            guard let date = Self.dateFormatter.date(from: releaseDate) else { return nil }
            // Prefer the pipeline's distributor-based estimate; otherwise the
            // same popularity heuristic as the direct TMDB path. Trading
            // moves the number from here.
            let popularity = min(200, max(1, self.popularity ?? 30))
            let estimate = estimatedOpeningMillions ?? (2.0 + popularity / 3.5)
            return Movie(
                id: id,
                title: title,
                studio: distributor ?? "—",
                releaseDate: date,
                posterEmoji: TMDBMovieProvider.emojiForGenre(genre),
                posterURL: posterURL,
                tagline: overview?.split(separator: ".").first.map { String($0) + "." } ?? title,
                consensusOpeningMillions: max(1, estimate.rounded()),
                impliedVolPct: max(20.0, 80.0 - popularity * 0.25).rounded(),
                genre: genre ?? "—",
                addedAt: Date(),
                synopsis: overview
            )
        }
    }
}

extension Config {
    /// Every source that can list upcoming films. Later sources win when two
    /// list the same title, so the hand-verified slate — curated dates,
    /// cast and stable ids that open positions refer to — has the last word.
    static var compositeProvider: MovieDataProvider {
        var sources: [MovieDataProvider] = []
        if !tmdbAPIKey.isEmpty {
            sources.append(TMDBMovieProvider(apiKey: tmdbAPIKey))
        }
        sources.append(PublishedCatalogProvider())
        sources.append(VerifiedMovieProvider())
        return CompositeMovieProvider(sources)
    }
}
