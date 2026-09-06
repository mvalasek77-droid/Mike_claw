import Foundation

/// The consolidated market for one contract: every agent's quote plus
/// the best bid and offer assembled from them.
struct QuoteBook: Identifiable, Hashable {
    let contractId: String
    let movieId: String
    /// Best bid and offer across the whole desk.
    let nbbo: Quote
    /// Every agent's individual market, in roster order.
    let quotes: [AgentQuote]
    /// The crowd read the agents quoted against.
    let pulse: SentimentPulse
    /// Theoretical value before agent opinion.
    let fairValue: Double
    /// Who is on the inside, if anyone.
    let bestBidAgent: String?
    let bestAskAgent: String?
    /// True when two agents wanted to trade with each other and the desk
    /// had to resolve it. A crossed book means real disagreement and
    /// produces a very tight print.
    let crossed: Bool

    var id: String { contractId }

    /// Agents currently showing size on at least one side.
    var activeAgents: [AgentQuote] { quotes.filter(\.isQuoting) }
    /// Agents that have pulled out entirely.
    var steppedAway: [AgentQuote] { quotes.filter { !$0.isQuoting } }

    /// The printed mark the rest of the app consumes.
    var mark: Double { nbbo.mid }

    /// Headline description of the market state, for the desk banner.
    var headline: String {
        if steppedAway.count >= 2 {
            return "\(steppedAway.count) agents stepped away"
        }
        if crossed { return "Agents crossed — market printed tight" }
        return nbbo.liquidityGrade.label + " market"
    }

    static func == (lhs: QuoteBook, rhs: QuoteBook) -> Bool {
        lhs.contractId == rhs.contractId
            && lhs.nbbo == rhs.nbbo
            && lhs.quotes == rhs.quotes
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(contractId)
        hasher.combine(nbbo)
    }
}

/// Assembles many agents into one two-sided market.
///
/// This is the piece that makes the desk feel alive: the inside market
/// is not one model's output, it is whichever agent is currently most
/// willing to trade. When the agents agree the spread collapses; when
/// sentiment fractures them the spread blows out on its own, with no
/// special-case code for "volatile" states.
struct MarketMakingDesk {
    var agents: [MarketMakingAgent]
    /// Prices within this distance of the best count as being *at* the
    /// best, and their size joins the top of book.
    var levelTolerance: Double = 0.015
    /// Narrowest market the desk will ever publish.
    var minSpread: Double = 0.02
    /// Fallback half-spread used when a whole side goes unquoted.
    var noQuoteHalfSpread: Double = 0.22

    init(agents: [MarketMakingAgent] = AgentRoster.standard()) {
        self.agents = agents
    }

    /// Build the consolidated book for one contract.
    ///
    /// - Parameter seed: fixes the agents' random jitter. Defaults to a
    ///   stable hash of the contract id, so the same context always
    ///   yields the same book — pass an explicit seed in tests, or a
    ///   rotating one in production to keep the tape moving.
    func makeBook(_ ctx: QuoteContext, seed: UInt64? = nil) -> QuoteBook {
        var rng = seed.map { SeededGenerator(seed: $0) }
            ?? SeededGenerator(seed: ctx.contract.id)

        let quotes = agents.map { $0.quote(ctx, rng: &rng) }
        let nbbo = consolidate(quotes, fairValue: ctx.fairValue)

        return QuoteBook(
            contractId: ctx.contract.id,
            movieId: ctx.contract.movieId,
            nbbo: nbbo.quote,
            quotes: quotes,
            pulse: ctx.pulse,
            fairValue: ctx.fairValue,
            bestBidAgent: nbbo.bidAgent,
            bestAskAgent: nbbo.askAgent,
            crossed: nbbo.crossed
        )
    }

    // MARK: - Consolidation

    private struct Consolidated {
        let quote: Quote
        let bidAgent: String?
        let askAgent: String?
        let crossed: Bool
    }

    /// Best bid = the highest price anyone will pay, with the size of
    /// everyone at that level. Best ask = the lowest anyone will sell
    /// at. Agents showing zero size are not in the market.
    private func consolidate(_ quotes: [AgentQuote], fairValue: Double) -> Consolidated {
        let bidders = quotes.filter { $0.bidSize > 0 }
        let askers  = quotes.filter { $0.askSize > 0 }

        let topBid = bidders.max { $0.bid < $1.bid }
        let topAsk = askers.min { $0.ask < $1.ask }

        // A side with nobody on it still needs a price, or the UI has
        // nothing to draw and takers have nothing to cross. Quote it far
        // away with zero size so it reads as "no bid" / "no offer".
        let bidPrice = topBid?.bid ?? max(0.05, fairValue * (1 - noQuoteHalfSpread))
        let askPrice = topAsk?.ask ?? fairValue * (1 + noQuoteHalfSpread)

        let bidSize = bidders
            .filter { $0.bid >= bidPrice - levelTolerance }
            .reduce(0) { $0 + $1.bidSize }
        let askSize = askers
            .filter { $0.ask <= askPrice + levelTolerance }
            .reduce(0) { $0 + $1.askSize }

        // Crossed: one agent bids above where another offers. In a real
        // book they trade and the market reprints tight around where
        // they crossed. Reproducing that is what makes a sentiment flip
        // look like a violent, high-conviction move rather than a bug.
        if bidPrice >= askPrice {
            let crossMid = (bidPrice + askPrice) / 2
            let half = max(minSpread / 2, crossMid * 0.004)
            let resolved = Quote(bid: crossMid - half,
                                 ask: crossMid + half,
                                 bidSize: bidSize,
                                 askSize: askSize).rounded()
            return Consolidated(quote: resolved,
                                bidAgent: topBid?.agentName,
                                askAgent: topAsk?.agentName,
                                crossed: true)
        }

        var quote = Quote(bid: bidPrice, ask: askPrice,
                          bidSize: bidSize, askSize: askSize).rounded()

        // Enforce the floor width after rounding.
        if quote.spread < minSpread {
            let mid = quote.mid
            quote = Quote(bid: mid - minSpread / 2, ask: mid + minSpread / 2,
                          bidSize: quote.bidSize, askSize: quote.askSize).rounded()
        }

        return Consolidated(quote: quote,
                            bidAgent: topBid?.agentName,
                            askAgent: topAsk?.agentName,
                            crossed: false)
    }
}

// MARK: - Desk-wide aggregates

/// Roll-up of what the desk is doing across every contract on a movie.
/// Powers the summary header on the Trading Desk screen.
struct DeskSummary: Hashable {
    let movieId: String
    let contractsQuoted: Int
    let averageSpreadPct: Double
    let averageImbalance: Double
    let steppedAwayCount: Int
    let crossedCount: Int
    let pulse: SentimentPulse

    var grade: LiquidityGrade {
        switch averageSpreadPct {
        case ..<0.02:  return .deep
        case ..<0.05:  return .healthy
        case ..<0.10:  return .thin
        default:       return .fractured
        }
    }

    /// One line for the header. Leads with whatever is most unusual.
    var headline: String {
        if steppedAwayCount >= 3 {
            return "Liquidity is draining — \(steppedAwayCount) agent quotes pulled."
        }
        if crossedCount > 0 {
            return "Agents crossing on \(crossedCount) line\(crossedCount == 1 ? "" : "s") — conviction is high."
        }
        if averageImbalance > 0.25 { return "Size is stacked on the bid. Buyers in control." }
        if averageImbalance < -0.25 { return "Size is stacked on the offer. Sellers in control." }
        return grade.blurb
    }

    static func build(movieId: String, books: [QuoteBook], pulse: SentimentPulse) -> DeskSummary {
        guard !books.isEmpty else {
            return DeskSummary(movieId: movieId, contractsQuoted: 0,
                               averageSpreadPct: 0, averageImbalance: 0,
                               steppedAwayCount: 0, crossedCount: 0, pulse: pulse)
        }
        let n = Double(books.count)
        return DeskSummary(
            movieId: movieId,
            contractsQuoted: books.count,
            averageSpreadPct: books.reduce(0) { $0 + $1.nbbo.spreadPct } / n,
            averageImbalance: books.reduce(0) { $0 + $1.nbbo.imbalance } / n,
            steppedAwayCount: books.reduce(0) { $0 + $1.steppedAway.count },
            crossedCount: books.filter(\.crossed).count,
            pulse: pulse
        )
    }
}
