import Foundation

/// Fetches actual opening-weekend grosses from the published data set
/// and settles open positions automatically.
///
/// The production path: a scheduled GitHub Action scrapes free public
/// sources (Box Office Mojo via the published data set, with The Numbers
/// as a fallback), writes `actuals.json` to GitHub Pages, and this
/// service pulls that file on app launch. When the data set has an
/// actual for a movie the user holds a position on, the position is
/// settled at that number.
///
/// Positions wait for the reported number — settling early on a guess
/// would permanently skew the profit leaderboard. Only if no number has
/// been published a full week after the Monday settlement (the pipeline
/// is down, or the film had no reported opening) does the market
/// simulation settle the movie, so nobody is left in limbo.
@MainActor
final class SettlementService: ObservableObject {
    static let shared = SettlementService()

    @Published private(set) var lastCheckAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var settledThisSession: Int = 0

    private let session: URLSession
    private let baseURL: URL

    private init(
        session: URLSession = .shared,
        baseURL: URL = Config.dataAPIBaseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    /// Check for settleable movies and settle any open positions.
    /// Called on app launch and after catalog refreshes.
    func checkAndSettle() async {
        let portfolio = PortfolioService.shared
        let market = MarketService.shared

        let openMovieIds = Set(
            portfolio.positions
                .filter { $0.isOpen }
                .map { $0.movieId }
        )
        guard !openMovieIds.isEmpty else { return }

        let settledMovies = market.movies.filter { movie in
            openMovieIds.contains(movie.id) && movie.isSettled
        }
        guard !settledMovies.isEmpty else { return }

        let actuals = await fetchActuals()
        lastCheckAt = Date()

        var count = 0
        for movie in settledMovies {
            let hasOpenPositions = portfolio.positions.contains {
                $0.movieId == movie.id && $0.isOpen
            }
            guard hasOpenPositions else { continue }

            let actual = actuals[movie.id]
                ?? actuals[movie.title.lowercased()]
                ?? Self.knownActuals[movie.id]
            if let actual {
                portfolio.settle(movieId: movie.id, actualMillions: actual)
            } else if Date() > movie.opensAt.addingTimeInterval(Self.simulationFallbackAfter) {
                let simulated = market.simulatedActualOW(for: movie)
                portfolio.settle(movieId: movie.id, actualMillions: simulated)
            } else {
                continue
            }
            count += 1
        }

        if count > 0 {
            settledThisSession += count
            portfolio.refreshLeaderboard()
        }
    }

    /// Opening Friday + 10 days = one week after the normal Monday settlement.
    private static let simulationFallbackAfter: TimeInterval = 10 * 86400

    // MARK: - Known actuals for seed movies

    private static let knownActuals: [String: Double] = [
        "m_practical_magic2": 30.0,
    ]

    // MARK: - Data fetching

    private func fetchActuals() async -> [String: Double] {
        let url = baseURL.appendingPathComponent("actuals.json")
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            // Results land Monday; a cached copy from Sunday would hide them.
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return [:]
            }
            let envelope = try JSONDecoder().decode(ActualsEnvelope.self, from: data)
            var result: [String: Double] = [:]
            for (key, entry) in envelope.actuals {
                result[key] = entry.domesticOpeningMillions
                if let title = entry.title {
                    result[title.lowercased()] = entry.domesticOpeningMillions
                }
            }
            lastError = nil
            return result
        } catch {
            lastError = error.localizedDescription
            return [:]
        }
    }
}

// MARK: - Wire format

private struct ActualsEnvelope: Decodable {
    let version: Int
    let generatedAt: String?
    let actuals: [String: ActualEntry]
}

private struct ActualEntry: Decodable {
    let title: String?
    let domesticOpeningMillions: Double
    let source: String?
    let reportedAt: String?
}
