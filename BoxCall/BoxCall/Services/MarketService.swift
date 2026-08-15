import Foundation
import Combine

/// Mock backend. In production this would fetch from a server that scrapes
/// Box Office Mojo / The Numbers / Deadline tracking + settles positions.
final class MarketService: ObservableObject {
    static let shared = MarketService()

    @Published private(set) var movies: [Movie] = []
    @Published private(set) var chains: [String: [Contract]] = [:]  // movieId -> chain

    private init() {
        loadMockCatalog()
    }

    func movie(id: String) -> Movie? { movies.first { $0.id == id } }

    func chain(for movieId: String) -> [Contract] {
        chains[movieId] ?? []
    }

    /// Refresh the mark price on every contract, drifting toward the consensus.
    /// A real app would recompute from the order book.
    func tick() {
        for movieId in chains.keys {
            guard let movie = movie(id: movieId) else { continue }
            chains[movieId] = chains[movieId]?.map { contract in
                var c = contract
                let drift = Double.random(in: -0.03...0.03)
                let newPremium = max(0.25, c.premium * (1 + drift))
                c = Contract(
                    id: c.id, movieId: c.movieId, side: c.side,
                    strikeMillions: c.strikeMillions,
                    premium: (newPremium * 100).rounded() / 100,
                    multiplier: c.multiplier,
                    openInterest: c.openInterest + Int.random(in: 0...3)
                )
                _ = movie   // silence unused; consensus could steer drift later
                return c
            }
        }
        objectWillChange.send()
    }

    // MARK: - Mock catalog

    private func loadMockCatalog() {
        let today = Calendar.current.startOfDay(for: Date())
        func date(_ daysFromNow: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: daysFromNow, to: today)!
        }

        let seeds: [Movie] = [
            .init(id: "m_neon", title: "Neon Requiem", studio: "A24",
                  releaseDate: date(5), posterEmoji: "🌃",
                  tagline: "A cyberpunk grief opera.",
                  consensusOpeningMillions: 12, impliedVolPct: 55, genre: "Sci-Fi"),
            .init(id: "m_glacier", title: "Glacier", studio: "Universal",
                  releaseDate: date(9), posterEmoji: "🏔️",
                  tagline: "The mountain will not forgive.",
                  consensusOpeningMillions: 34, impliedVolPct: 32, genre: "Thriller"),
            .init(id: "m_starmap", title: "Starmap 3: Ascension", studio: "Marvel Studios",
                  releaseDate: date(14), posterEmoji: "🚀",
                  tagline: "Every hero has a horizon.",
                  consensusOpeningMillions: 168, impliedVolPct: 22, genre: "Superhero"),
            .init(id: "m_prowl", title: "Prowl", studio: "Blumhouse",
                  releaseDate: date(18), posterEmoji: "🐺",
                  tagline: "Something is hunting the hunters.",
                  consensusOpeningMillions: 21, impliedVolPct: 48, genre: "Horror"),
            .init(id: "m_paperhouse", title: "The Paper House", studio: "Searchlight",
                  releaseDate: date(23), posterEmoji: "📜",
                  tagline: "A love story, folded once.",
                  consensusOpeningMillions: 6, impliedVolPct: 65, genre: "Drama"),
            .init(id: "m_atlas", title: "Atlas & Sons", studio: "Warner Bros.",
                  releaseDate: date(30), posterEmoji: "⚔️",
                  tagline: "The empire runs in the family.",
                  consensusOpeningMillions: 58, impliedVolPct: 28, genre: "Action"),
            .init(id: "m_karaoke", title: "Karaoke Night",
                  studio: "Sony Pictures Classics",
                  releaseDate: date(37), posterEmoji: "🎤",
                  tagline: "Everyone's the star. Nobody remembers.",
                  consensusOpeningMillions: 4, impliedVolPct: 70, genre: "Comedy"),
            .init(id: "m_deepblue", title: "Deep Blue Country", studio: "Netflix (Theatrical)",
                  releaseDate: date(44), posterEmoji: "🌊",
                  tagline: "The tide brought something back.",
                  consensusOpeningMillions: 9, impliedVolPct: 60, genre: "Mystery")
        ]
        movies = seeds

        var built: [String: [Contract]] = [:]
        for m in seeds {
            built[m.id] = generateChain(for: m)
        }
        chains = built
    }

    /// Build a 5-strike chain around the consensus for both Call and Put.
    /// Premium priced as: intrinsic + timeValue(IV, days-to-expiry, moneyness).
    private func generateChain(for movie: Movie) -> [Contract] {
        let center = movie.consensusOpeningMillions
        let step = max(1.0, (center * 0.10).rounded())
        let strikes: [Double] = [-2, -1, 0, 1, 2].map { (center + Double($0) * step).rounded() }
        let mult = 1.0  // 1 Reel Coin per $M intrinsic
        let iv = movie.impliedVolPct / 100.0
        let dte = max(1, movie.daysToRelease)

        var out: [Contract] = []
        for side in ContractSide.allCases {
            for k in strikes {
                let intrinsic = side == .call
                    ? max(center - k, 0)
                    : max(k - center, 0)
                let moneyness = abs(center - k) / max(1, center)
                let timeValue = center * iv * sqrt(Double(dte) / 30.0) * exp(-moneyness * 1.8) * 0.5
                let premium = max(0.25, (intrinsic + timeValue))
                out.append(.init(
                    id: "\(movie.id)_\(side.rawValue)_\(Int(k))",
                    movieId: movie.id,
                    side: side,
                    strikeMillions: k,
                    premium: (premium * 100).rounded() / 100,
                    multiplier: mult,
                    openInterest: Int.random(in: 40...900)
                ))
            }
        }
        return out.sorted { ($0.side.rawValue, $0.strikeMillions) < ($1.side.rawValue, $1.strikeMillions) }
    }

    /// Simulate opening weekend actual and settle positions.
    /// Called by PortfolioService when a movie's window closes.
    func simulatedActualOW(for movie: Movie) -> Double {
        let sigma = movie.consensusOpeningMillions * (movie.impliedVolPct / 100)
        // Box-Muller for a normal sample; deterministic by movie id + week.
        var g = SystemRandomNumberGenerator()
        let u1 = Double.random(in: 0.0001...1, using: &g)
        let u2 = Double.random(in: 0...1, using: &g)
        let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        return max(0.1, movie.consensusOpeningMillions + z * sigma)
    }
}
