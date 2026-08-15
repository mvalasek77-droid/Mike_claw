import Foundation
import Combine

/// Live market. Premium moves continuously as users and NPCs trade,
/// plus periodic news events shock a movie's whole chain.
///
/// Pricing model per contract:
///   mark = basePremium × exp(demand / liquidity) × movieSentiment × (1 + micro-noise)
///
/// Positive demand (net buys) drives mark up; negative (net sells) drops it.
/// A single movie-wide sentiment multiplier moves ALL of a movie's strikes
/// in one direction when a news event lands — bullish news lifts Calls
/// and drops Puts; bearish news does the reverse.
final class MarketService: ObservableObject {
    static let shared = MarketService()

    @Published private(set) var movies: [Movie] = []
    @Published private(set) var chains: [String: [Contract]] = [:]
    @Published private(set) var history: [String: [PricePoint]] = [:]     // contractId
    @Published private(set) var consensusHistory: [String: [PricePoint]] = [:]  // movieId
    @Published private(set) var recentEvents: [MarketEvent] = []
    @Published private(set) var lastTickAt: Date = Date()

    // Per-contract signed demand imbalance (unitless).
    private var demand: [String: Double] = [:]
    // Per-movie sentiment multiplier drifting near 1.0 (0.5 - 1.5 realistic).
    private var movieSentiment: [String: Double] = [:]
    // Per-contract per-side liquidity — higher = less slippage.
    private let liquidity: Double = 80.0
    // Rolling history window (points per contract).
    private let historyCap: Int = 90

    private var updateTimer: Timer?
    private let tickInterval: TimeInterval = 3.0

    private init() {
        loadMockCatalog()
    }

    // MARK: - Lifecycle

    func startMarket() {
        guard updateTimer == nil else { return }
        // First tick immediately so charts have >1 point on first render.
        tick()
        updateTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopMarket() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Read

    func movie(id: String) -> Movie? { movies.first { $0.id == id } }
    func chain(for movieId: String) -> [Contract] { chains[movieId] ?? [] }
    func priceHistory(contractId: String) -> [PricePoint] { history[contractId] ?? [] }
    func consensusHistoryFor(movieId: String) -> [PricePoint] { consensusHistory[movieId] ?? [] }
    func events(for movieId: String) -> [MarketEvent] {
        recentEvents.filter { $0.movieId == movieId }
    }

    /// The current crowd-forecast opening. Base tracker × movie sentiment,
    /// where sentiment is nudged by every buy/sell/news event on the movie.
    func impliedConsensus(for movieId: String) -> Double {
        guard let m = movie(id: movieId) else { return 0 }
        let s = movieSentiment[movieId] ?? 1.0
        return (m.consensusOpeningMillions * s * 10).rounded() / 10
    }

    /// Percentage change vs the original tracker number.
    func consensusDeltaPct(for movieId: String) -> Double {
        guard let m = movie(id: movieId), m.consensusOpeningMillions > 0 else { return 0 }
        return (impliedConsensus(for: movieId) - m.consensusOpeningMillions) / m.consensusOpeningMillions
    }

    // MARK: - Trade hooks (called by PortfolioService)

    func recordBuy(contractId: String, quantity: Int) {
        demand[contractId, default: 0] += Double(quantity)
        // Buying a Call is a mildly bullish signal for the whole movie;
        // buying a Put is mildly bearish.
        if let c = findContract(contractId) {
            let bump = Double(quantity) * 0.002 * (c.side == .call ? 1 : -1)
            movieSentiment[c.movieId, default: 1.0] =
                clamp((movieSentiment[c.movieId] ?? 1.0) + bump, 0.5, 1.5)
        }
        tickImmediate()
    }

    func recordSell(contractId: String, quantity: Int) {
        demand[contractId, default: 0] -= Double(quantity)
        tickImmediate()
    }

    private func findContract(_ id: String) -> Contract? {
        for chain in chains.values {
            if let c = chain.first(where: { $0.id == id }) { return c }
        }
        return nil
    }

    // MARK: - Tick

    /// Public, hand-driven tick (used after user trades so their fill
    /// reflects on the chart immediately without waiting up to 3s).
    private func tickImmediate() { tick() }

    private func tick() {
        // 1. NPC trader activity across a small random slice of contracts.
        simulateNPCTraders()

        // 2. Occasionally inject a news event that shocks a random movie.
        maybeInjectEvent()

        // 3. Drift demand slowly back toward zero (mean reversion).
        for k in demand.keys {
            demand[k] = (demand[k] ?? 0) * 0.995
        }
        // Drift sentiment toward 1.0.
        for k in movieSentiment.keys {
            let s = movieSentiment[k] ?? 1.0
            movieSentiment[k] = s + (1.0 - s) * 0.02
        }

        // 4. Recompute marks and append to history.
        let now = Date()
        var newChains: [String: [Contract]] = [:]
        for (mid, chain) in chains {
            let sentiment = movieSentiment[mid] ?? 1.0
            newChains[mid] = chain.map { c in
                let d = demand[c.id] ?? 0
                let sideBias = c.side == .call ? sentiment : (2 - sentiment)
                let noise = Double.random(in: -0.01...0.01)
                var mark = c.basePremium * exp(d / liquidity) * sideBias * (1 + noise)
                mark = max(0.25, (mark * 100).rounded() / 100)
                // Small open-interest tick to look alive.
                let oi = c.openInterest + Int.random(in: 0...2)

                appendHistory(contractId: c.id, mark: mark, at: now)

                return Contract(
                    id: c.id, movieId: c.movieId, side: c.side,
                    strikeMillions: c.strikeMillions,
                    basePremium: c.basePremium,
                    premium: mark,
                    multiplier: c.multiplier,
                    openInterest: oi
                )
            }
        }
        chains = newChains

        // Append consensus point per movie.
        for m in movies {
            let c = impliedConsensus(for: m.id)
            var pts = consensusHistory[m.id] ?? []
            pts.append(.init(time: now, mark: c))
            if pts.count > historyCap { pts.removeFirst(pts.count - historyCap) }
            consensusHistory[m.id] = pts
        }

        lastTickAt = now
    }

    private func appendHistory(contractId: String, mark: Double, at time: Date) {
        var pts = history[contractId] ?? []
        pts.append(.init(time: time, mark: mark))
        if pts.count > historyCap { pts.removeFirst(pts.count - historyCap) }
        history[contractId] = pts
    }

    private func simulateNPCTraders() {
        // Pick a few contracts at random and nudge demand up or down.
        let allIds = chains.values.flatMap { $0 }.map(\.id)
        guard !allIds.isEmpty else { return }
        let hits = Int.random(in: 2...5)
        for _ in 0..<hits {
            guard let id = allIds.randomElement() else { break }
            let dir: Double = Bool.random() ? 1 : -1
            let size = Double.random(in: 1...6)
            demand[id, default: 0] += dir * size
        }
    }

    private func maybeInjectEvent() {
        // ~5% chance per tick.
        guard Double.random(in: 0...1) < 0.05, let movie = movies.randomElement() else { return }
        let bullish = Bool.random()
        let magnitude = (bullish ? 1 : -1) * Double.random(in: 0.05...0.25)
        let headline = bullish
            ? MarketEvent.bullishHeadlines.randomElement()!
            : MarketEvent.bearishHeadlines.randomElement()!
        let event = MarketEvent(
            id: UUID(), time: Date(),
            movieId: movie.id, movieTitle: movie.title,
            headline: headline, magnitude: magnitude
        )
        recentEvents.insert(event, at: 0)
        if recentEvents.count > 25 { recentEvents = Array(recentEvents.prefix(25)) }

        // Apply the shock to the movie's whole chain via sentiment.
        let current = movieSentiment[movie.id] ?? 1.0
        movieSentiment[movie.id] = clamp(current + magnitude, 0.5, 1.5)

        // Also drop an inbox notification for the user IF they hold any
        // position on this movie (news matters when you're exposed).
        if PortfolioService.shared.positions.contains(where: {
            $0.movieId == movie.id && $0.isOpen
        }) {
            NotificationsService.shared.notifyMarketEvent(event)
        }
    }

    private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(x, lo), hi)
    }

    // MARK: - Mock catalog + chain generation

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
            movieSentiment[m.id] = 1.0
        }
        chains = built
    }

    private func generateChain(for movie: Movie) -> [Contract] {
        let center = movie.consensusOpeningMillions
        let step = max(1.0, (center * 0.10).rounded())
        let strikes: [Double] = [-2, -1, 0, 1, 2].map { (center + Double($0) * step).rounded() }
        let mult = 1.0
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
                let fair = max(0.25, (intrinsic + timeValue))
                let rounded = (fair * 100).rounded() / 100
                out.append(.init(
                    id: "\(movie.id)_\(side.rawValue)_\(Int(k))",
                    movieId: movie.id,
                    side: side,
                    strikeMillions: k,
                    basePremium: rounded,
                    premium: rounded,
                    multiplier: mult,
                    openInterest: Int.random(in: 40...900)
                ))
            }
        }
        return out.sorted { ($0.side.rawValue, $0.strikeMillions) < ($1.side.rawValue, $1.strikeMillions) }
    }

    // MARK: - Settlement demo

    func simulatedActualOW(for movie: Movie) -> Double {
        let sigma = movie.consensusOpeningMillions * (movie.impliedVolPct / 100)
        var g = SystemRandomNumberGenerator()
        let u1 = Double.random(in: 0.0001...1, using: &g)
        let u2 = Double.random(in: 0...1, using: &g)
        let z = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        return max(0.1, movie.consensusOpeningMillions + z * sigma)
    }
}
