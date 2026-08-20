import Foundation

/// The pre-release tracking number for a movie — the crowd/analyst
/// estimate of opening-weekend domestic gross in $M, plus an implied
/// volatility estimate (how wide the plausible outcome range is).
///
/// This is a SEPARATE concern from the upcoming-releases catalog
/// (MovieDataProvider). Titles come from one place; tracking numbers
/// come from another. In production, tracking is a paid feed
/// (National Research Group) or scraped from Deadline / The Numbers.
struct Tracking: Hashable {
    let openingWeekendMillions: Double
    let impliedVolPct: Double
}

protocol TrackingDataSource {
    /// Fetch tracking for a movie. May be nil when data isn't available
    /// yet (obscure indie, very early tracking window).
    func tracking(for movie: Movie) async -> Tracking?
}

// MARK: - Algorithmic (uses whatever the provider already returned)

/// Uses the estimates the MovieDataProvider already computed from
/// popularity / budget when it built the Movie. Zero-network fallback
/// so the app always has SOMETHING to price against.
final class AlgorithmicTrackingSource: TrackingDataSource {
    func tracking(for movie: Movie) async -> Tracking? {
        Tracking(
            openingWeekendMillions: movie.consensusOpeningMillions,
            impliedVolPct: movie.impliedVolPct
        )
    }
}

// MARK: - Backend (real tracking)

/// The production path. Calls the BoxCall backend which aggregates
/// pre-release tracking from Deadline / The Numbers / NRG feeds
/// server-side and returns a normalized number. Stubbed here — the
/// endpoint just doesn't exist yet — but the shape is real.
final class BoxCallBackendTrackingSource: TrackingDataSource {
    let baseURL: URL
    let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(baseURL: URL = URL(string: "https://api.boxcall.com")!,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func tracking(for movie: Movie) async -> Tracking? {
        var comps = URLComponents(url: baseURL.appendingPathComponent("tracking"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "movie_id", value: movie.id)]
        guard let url = comps.url else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try decoder.decode(Tracking.self, from: data)
        } catch {
            return nil
        }
    }
}

// MARK: - Composite with graceful fallback

/// Tries sources in order. First one that returns a non-nil Tracking
/// wins. Guaranteed to produce a Tracking as long as the final source
/// is the algorithmic fallback.
final class CompositeTrackingSource: TrackingDataSource {
    private let sources: [TrackingDataSource]

    init(_ sources: [TrackingDataSource]) { self.sources = sources }

    func tracking(for movie: Movie) async -> Tracking? {
        for source in sources {
            if let t = await source.tracking(for: movie) { return t }
        }
        return nil
    }
}

extension Config {
    /// The tracking source stack: backend if available (currently stubbed
    /// so it will 404 and fall through), then the algorithmic estimate.
    static var trackingSource: TrackingDataSource {
        CompositeTrackingSource([
            BoxCallBackendTrackingSource(),
            AlgorithmicTrackingSource()
        ])
    }
}

// MARK: - Codable helper for the backend shape

extension Tracking: Codable {
    enum CodingKeys: String, CodingKey {
        case openingWeekendMillions = "openingWeekendMillions"
        case impliedVolPct = "impliedVolPct"
    }
}
