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
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var refreshInFlight: Bool = false
    @Published private(set) var lastRefreshError: String?

    /// Rolling support / resistance per contract, refreshed each tick.
    @Published private(set) var srLevels: [String: SRLevel] = [:]

    var provider: MovieDataProvider = Config.preferredProvider
    var trackingSource: TrackingDataSource = Config.trackingSource
    var priceSetter: PriceSetter = PriceSetter()
    private var refreshTimer: Timer?

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

    // MARK: - Catalog refresh

    /// Fetch upcoming releases from the current data provider and merge
    /// into the live catalog. Preserves any chains, price history, and
    /// user positions on movies that survive across refreshes.
    @MainActor
    func refreshCatalog(windowDays: Int = 60) async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        do {
            let fetched = try await provider.fetchUpcoming(windowDays: windowDays)
            let newlyAddedIds = merge(remote: fetched)
            lastRefreshAt = Date()
            lastRefreshError = nil
            if !newlyAddedIds.isEmpty {
                await enrichTracking(for: newlyAddedIds)
            }
        } catch {
            lastRefreshError = error.localizedDescription
        }
    }

    /// Merge remote movies with the local catalog:
    /// - Existing movie ids get their metadata refreshed (poster, tagline, etc)
    ///   without touching the chain or history.
    /// - New ids get freshly generated chains and are marked as NEW.
    /// - Local-only movies (mock seeds not in remote) are kept as long as
    ///   they haven't opened yet OR the user has an open position on them.
    @discardableResult
    private func merge(remote: [Movie]) -> Set<String> {
        var byId: [String: Movie] = Dictionary(uniqueKeysWithValues: movies.map { ($0.id, $0) })
        var chainsById = chains
        var addedIds: Set<String> = []

        for r in remote {
            if let existing = byId[r.id] {
                // Refresh metadata; keep addedAt so NEW badge doesn't retrigger.
                byId[r.id] = Movie(
                    id: existing.id, title: r.title, studio: r.studio,
                    releaseDate: r.releaseDate, posterEmoji: r.posterEmoji,
                    posterURL: r.posterURL, tagline: r.tagline,
                    consensusOpeningMillions: existing.consensusOpeningMillions,
                    impliedVolPct: existing.impliedVolPct,
                    genre: r.genre, addedAt: existing.addedAt)
            } else {
                byId[r.id] = r
                chainsById[r.id] = generateChain(for: r)
                movieSentiment[r.id] = 1.0
                addedIds.insert(r.id)
            }
        }

        // Prune old local movies that already opened and have no open positions.
        let openMovieIds = Set(PortfolioService.shared.positions
            .filter { $0.isOpen }.map { $0.movieId })
        let remoteIds = Set(remote.map(\.id))
        for (id, m) in byId {
            if remoteIds.contains(id) { continue }
            if openMovieIds.contains(id) { continue }
            if !m.isSettled { continue }
            byId.removeValue(forKey: id)
            chainsById.removeValue(forKey: id)
            history = history.filter { !$0.key.hasPrefix(id) }
            consensusHistory.removeValue(forKey: id)
        }

        // Publish. Sort by release date so the Slate lists soonest first.
        movies = Array(byId.values).sorted { $0.releaseDate < $1.releaseDate }
        chains = chainsById
        return addedIds
    }

    // MARK: - Auto-refresh timer

    /// Refresh every 6 hours in the background while the app is open.
    private let refreshInterval: TimeInterval = 6 * 3600
    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            Task { @MainActor in await MarketService.shared.refreshCatalog() }
        }
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
    func srLevel(contractId: String) -> SRLevel? { srLevels[contractId] }

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
        // 1. Market makers step in at support / resistance across the book.
        runMarketMakers()

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

        // 5. Recompute S/R per contract now that history has one more point.
        var newSR: [String: SRLevel] = [:]
        for chain in chains.values {
            for c in chain {
                if let lvl = MarketMaker.levels(from: history[c.id] ?? []) {
                    newSR[c.id] = lvl
                }
            }
        }
        srLevels = newSR

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

    /// Market makers run on every contract every tick. For contracts with
    /// enough history, they compute S/R from recent prices and step in as
    /// buyers near support or sellers near resistance. Contracts with too
    /// little history get a mild random nudge so they can build a book.
    private func runMarketMakers() {
        for chain in chains.values {
            for c in chain {
                let hist = history[c.id] ?? []
                if let level = MarketMaker.levels(from: hist) {
                    let delta = MarketMaker.demandDelta(mark: c.premium, level: level)
                    demand[c.id, default: 0] += delta
                } else {
                    demand[c.id, default: 0] += Double.random(in: -2...2)
                }
            }
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
        let seeds = MockMovieProvider.builtInSeed()
        movies = seeds
        var built: [String: [Contract]] = [:]
        for m in seeds {
            built[m.id] = generateChain(for: m)
            movieSentiment[m.id] = 1.0
        }
        chains = built
    }

    /// Build the initial chain for a movie via PriceSetter, sourcing
    /// tracking synchronously from the movie's own estimate (the
    /// algorithmic path). Async enrichment from the backend is opt-in
    /// via `enrichTracking(for:)`.
    private func generateChain(for movie: Movie) -> [Contract] {
        let fallback = Tracking(
            openingWeekendMillions: movie.consensusOpeningMillions,
            impliedVolPct: movie.impliedVolPct
        )
        return priceSetter.chain(for: movie, tracking: fallback)
    }

    /// Optional post-merge step: hit the backend tracking source for
    /// a real number and, if it differs materially, re-seed the chain.
    /// Only fires on movies newly added this refresh.
    @MainActor
    func enrichTracking(for movieIds: Set<String>) async {
        for id in movieIds {
            guard let m = movie(id: id),
                  let t = await trackingSource.tracking(for: m) else { continue }
            let hasMeaningfulChange =
                abs(t.openingWeekendMillions - m.consensusOpeningMillions) > 0.5
                || abs(t.impliedVolPct - m.impliedVolPct) > 3
            guard hasMeaningfulChange else { continue }
            // Re-seed the chain against the real tracking.
            chains[id] = priceSetter.chain(for: m, tracking: t)
        }
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
