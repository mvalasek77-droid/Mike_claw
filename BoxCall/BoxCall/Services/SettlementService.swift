import Foundation

/// Settles open positions on the opening-weekend number as soon as it's
/// published — normally Sunday, when studios report weekend estimates.
///
/// The BoxCall Data workflow reads the weekend charts (Box Office Mojo,
/// The Numbers as fallback) hourly on Sunday and publishes every opening
/// in `actuals.json`. The first figure published for a film is frozen, so
/// every player settles on the same number. The app checks on launch, on
/// returning to the foreground, and every 15 minutes while open.
///
/// Positions wait for the reported number — settling early on a guess
/// would permanently skew the profit leaderboard. Only if no number has
/// been published three weeks after opening (the pipeline
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

    private static let minimumInterval: TimeInterval = 15 * 60

    /// For the app's minute timer: checks at most every 15 minutes.
    func checkIfDue() async {
        if let lastCheckAt, Date().timeIntervalSince(lastCheckAt) < Self.minimumInterval { return }
        await checkAndSettle()
    }

    /// Settles every open position on a movie that has opened and has a
    /// published opening number.
    func checkAndSettle() async {
        let portfolio = PortfolioService.shared
        let market = MarketService.shared

        let openMovieIds = Set(
            portfolio.positions
                .filter { $0.isOpen }
                .map { $0.movieId }
        )
        guard !openMovieIds.isEmpty else { return }

        // Opened (trading locked) is enough: results can land Sunday.
        let settledMovies = market.movies.filter { movie in
            openMovieIds.contains(movie.id) && !movie.isTradingOpen
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

            let actual = [actuals[movie.id], actuals[Movie.titleKey(movie.title)]]
                .compactMap { $0 }
                .first { $0.belongs(to: movie) }?.millions
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

    /// Three weeks after opening: long enough that a stalled data pipeline
    /// gets fixed before anyone is settled on a guess.
    private static let simulationFallbackAfter: TimeInterval = 21 * 86400

    // MARK: - Known actuals for seed movies

    private static let knownActuals: [String: Double] = [
        "m_practical_magic2": 30.0,
        "m_resident_evil": 60.1,     // Sep 18–20, 2026 domestic opening
    ]

    // MARK: - Data fetching

    /// A published opening, and the weekend it was reported for.
    struct PublishedOpening {
        let millions: Double
        let weekendOf: Date?

        /// A title match only counts for this film's own opening weekend:
        /// an older film with the same name ("The Mummy") must not settle it.
        func belongs(to movie: Movie) -> Bool {
            guard let weekendOf else { return true }
            // The reported weekend's Friday is on or after opening day
            // (Wednesday and Thursday openers report that Friday). A day of
            // slack covers time zones.
            let earliest = Calendar.current.date(byAdding: .day, value: -1, to: movie.opensAt) ?? movie.opensAt
            return weekendOf >= earliest
        }
    }

    private static let weekendFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func fetchActuals() async -> [String: PublishedOpening] {
        let url = baseURL.appendingPathComponent("actuals.json")
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            // Results land Sunday; a cached copy from earlier would hide them.
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return [:]
            }
            let envelope = try JSONDecoder().decode(ActualsEnvelope.self, from: data)
            var result: [String: PublishedOpening] = [:]
            for (key, entry) in envelope.actuals where entry.isOpeningWeekend ?? true {
                let opening = PublishedOpening(
                    millions: entry.domesticOpeningMillions,
                    weekendOf: entry.weekendOf.flatMap { Self.weekendFormatter.date(from: String($0.prefix(10))) })
                result[key] = opening
                if let title = entry.title {
                    let titleKey = Movie.titleKey(title)
                    // Two films can share a title; the newer opening wins.
                    if let existing = result[titleKey], let a = existing.weekendOf,
                       let b = opening.weekendOf, a > b { continue }
                    result[titleKey] = opening
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
    let isOpeningWeekend: Bool?
    let weekendOf: String?
    let source: String?
    let reportedAt: String?
}
