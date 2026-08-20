import Foundation

/// Merge multiple upcoming-movies providers into one deduped stream.
///
/// In production the composite is:
///   1. TMDB (direct, always on) — titles, posters, dates
///   2. BoxCall backend (`/upcoming`) — aggregates IMDb Coming Soon,
///      The Numbers, Deadline calendars via server-side scrapers
///   3. Anything else you plug in later
///
/// Later sources take priority when the same movie appears twice, so
/// richer metadata from the backend overrides the TMDB baseline.
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

    /// Normalize by lowercased title + release-week bucket so the same
    /// title from different providers merges even if IDs differ.
    private func dedupKey(for m: Movie) -> String {
        let cal = Calendar.current
        let year = cal.component(.year, from: m.releaseDate)
        let week = cal.component(.weekOfYear, from: m.releaseDate)
        return "\(m.title.lowercased())_\(year)_\(week)"
    }
}

// MARK: - Backend upcoming provider (aggregates IMDb / The Numbers server-side)

/// The production upcoming source. Hits your own /upcoming endpoint,
/// which internally scrapes IMDb Coming Soon, The Numbers release
/// calendar, and Deadline release schedule. Stubbed here — the endpoint
/// doesn't exist yet, so it returns [] gracefully and lets TMDB carry
/// the catalog.
final class BoxCallBackendUpcomingProvider: MovieDataProvider {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = URL(string: "https://api.boxcall.com")!,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchUpcoming(windowDays: Int) async throws -> [Movie] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("upcoming"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "window_days", value: "\(windowDays)")]
        guard let url = comps.url else { return [] }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let decoder = JSONDecoder()
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            decoder.dateDecodingStrategy = .formatted(df)
            let batch = try decoder.decode([Movie].self, from: data)
            return batch
        } catch {
            return []   // Backend not up yet — degrade gracefully.
        }
    }
}

extension Config {
    /// Overrides the earlier single-provider setup: builds a composite
    /// that combines every source the app knows about.
    static var compositeProvider: MovieDataProvider {
        var sources: [MovieDataProvider] = []
        if !tmdbAPIKey.isEmpty {
            sources.append(TMDBMovieProvider(apiKey: tmdbAPIKey))
        }
        sources.append(BoxCallBackendUpcomingProvider())
        if sources.isEmpty {
            return MockMovieProvider()
        }
        return CompositeMovieProvider(sources)
    }
}
