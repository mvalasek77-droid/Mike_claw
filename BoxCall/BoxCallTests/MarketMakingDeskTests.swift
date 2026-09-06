import XCTest
@testable import BoxCall

/// Tests for the piece that turns five opinionated agents into one
/// tradable market.
final class MarketMakingDeskTests: XCTestCase {

    // MARK: - Fixtures

    private func contract(side: ContractSide = .call) -> Contract {
        Contract(id: "m1_\(side.rawValue)_100", movieId: "m1", side: side,
                 strikeMillions: 100, basePremium: 10, premium: 10,
                 multiplier: 1, openInterest: 100)
    }

    private func ctx(side: ContractSide = .call,
                     fair: Double = 10,
                     score: Double = 0,
                     velocity: Double = 0,
                     volume: Double = 0.5,
                     dispersion: Double = 0.3,
                     dte: Int = 30) -> QuoteContext {
        QuoteContext(contract: contract(side: side),
                     fairValue: fair,
                     pulse: SentimentPulse(score: score, velocity: velocity,
                                           volume: volume, dispersion: dispersion),
                     daysToRelease: dte)
    }

    /// A stub that publishes exactly the market it is told to.
    private struct FixedAgent: MarketMakingAgent {
        let id: String
        var name: String { id }
        var blurb: String { "fixed" }
        var glyph: String { "circle" }
        var tint: AgentTint { .steel }
        let fixedBid: Double
        let fixedAsk: Double
        let fixedBidSize: Int
        let fixedAskSize: Int

        func quote(_ ctx: QuoteContext, rng: inout SeededGenerator) -> AgentQuote {
            AgentQuote(agentId: id, agentName: name, glyph: glyph, tint: tint,
                       quote: Quote(bid: fixedBid, ask: fixedAsk,
                                    bidSize: fixedBidSize, askSize: fixedAskSize),
                       stance: .balanced, rationale: "fixed")
        }
    }

    // MARK: - Best bid and offer

    func testNBBO_takesHighestBidAndLowestAsk() {
        let desk = MarketMakingDesk(agents: [
            FixedAgent(id: "a", fixedBid: 9.00, fixedAsk: 11.00, fixedBidSize: 5, fixedAskSize: 5),
            FixedAgent(id: "b", fixedBid: 9.50, fixedAsk: 10.40, fixedBidSize: 7, fixedAskSize: 3),
            FixedAgent(id: "c", fixedBid: 8.75, fixedAsk: 10.90, fixedBidSize: 2, fixedAskSize: 9)
        ])
        let book = desk.makeBook(ctx(), seed: 1)
        XCTAssertEqual(book.nbbo.bid, 9.50, accuracy: 0.001)
        XCTAssertEqual(book.nbbo.ask, 10.40, accuracy: 0.001)
        XCTAssertEqual(book.bestBidAgent, "b")
        XCTAssertEqual(book.bestAskAgent, "b")
    }

    func testNBBO_sumsSizeFromEveryAgentAtTheBest() {
        // Two agents bid the same price; their size should combine.
        let desk = MarketMakingDesk(agents: [
            FixedAgent(id: "a", fixedBid: 9.50, fixedAsk: 11.00, fixedBidSize: 5, fixedAskSize: 4),
            FixedAgent(id: "b", fixedBid: 9.50, fixedAsk: 11.00, fixedBidSize: 7, fixedAskSize: 6),
            FixedAgent(id: "c", fixedBid: 8.00, fixedAsk: 12.00, fixedBidSize: 99, fixedAskSize: 99)
        ])
        let book = desk.makeBook(ctx(), seed: 1)
        XCTAssertEqual(book.nbbo.bidSize, 12, "Size at the best must aggregate")
        XCTAssertEqual(book.nbbo.askSize, 10)
    }

    func testNBBO_ignoresAgentsShowingNoSize() {
        let desk = MarketMakingDesk(agents: [
            // Best price on paper, but zero size — not a real market.
            FixedAgent(id: "ghost", fixedBid: 9.90, fixedAsk: 10.10, fixedBidSize: 0, fixedAskSize: 0),
            FixedAgent(id: "real", fixedBid: 9.00, fixedAsk: 11.00, fixedBidSize: 5, fixedAskSize: 5)
        ])
        let book = desk.makeBook(ctx(), seed: 1)
        XCTAssertEqual(book.nbbo.bid, 9.00, accuracy: 0.001)
        XCTAssertEqual(book.nbbo.ask, 11.00, accuracy: 0.001)
        XCTAssertEqual(book.bestBidAgent, "real")
    }

    func testNBBO_handlesAnEmptySideWithoutCrossing() {
        let desk = MarketMakingDesk(agents: [
            FixedAgent(id: "bidonly", fixedBid: 9.00, fixedAsk: 11.00, fixedBidSize: 5, fixedAskSize: 0)
        ])
        let book = desk.makeBook(ctx(fair: 10), seed: 1)
        XCTAssertEqual(book.nbbo.askSize, 0, "Nobody is offering")
        XCTAssertGreaterThan(book.nbbo.ask, book.nbbo.bid)
        XCTAssertNil(book.bestAskAgent)
    }

    func testNBBO_handlesEveryAgentSteppingAway() {
        let desk = MarketMakingDesk(agents: [
            FixedAgent(id: "a", fixedBid: 9, fixedAsk: 11, fixedBidSize: 0, fixedAskSize: 0),
            FixedAgent(id: "b", fixedBid: 9, fixedAsk: 11, fixedBidSize: 0, fixedAskSize: 0)
        ])
        let book = desk.makeBook(ctx(fair: 10), seed: 1)
        XCTAssertEqual(book.nbbo.bidSize, 0)
        XCTAssertEqual(book.nbbo.askSize, 0)
        XCTAssertGreaterThan(book.nbbo.ask, book.nbbo.bid, "Must still publish a sane range")
        XCTAssertGreaterThan(book.nbbo.bid, 0)
        XCTAssertEqual(book.activeAgents.count, 0)
        XCTAssertEqual(book.steppedAway.count, 2)
    }

    // MARK: - Crossed markets

    func testCrossedBook_resolvesToATightUncrossedMarket() {
        // One agent bids 11 while another offers 10 — they would trade.
        let desk = MarketMakingDesk(agents: [
            FixedAgent(id: "aggressive", fixedBid: 11.00, fixedAsk: 13.00, fixedBidSize: 5, fixedAskSize: 5),
            FixedAgent(id: "seller", fixedBid: 8.00, fixedAsk: 10.00, fixedBidSize: 5, fixedAskSize: 5)
        ])
        let book = desk.makeBook(ctx(), seed: 1)
        XCTAssertTrue(book.crossed)
        XCTAssertGreaterThan(book.nbbo.ask, book.nbbo.bid, "Published market must never be crossed")
        XCTAssertEqual(book.nbbo.mid, 10.50, accuracy: 0.05, "Should print where they crossed")
        XCTAssertLessThan(book.nbbo.spreadPct, 0.02, "A cross prints tight")
    }

    // MARK: - Live roster behavior

    func testLiveRoster_producesValidBooksAcrossTheSentimentRange() {
        let desk = MarketMakingDesk()
        for score in stride(from: -1.0, through: 1.0, by: 0.25) {
            for velocity in stride(from: -1.0, through: 1.0, by: 0.5) {
                for side in ContractSide.allCases {
                    let book = desk.makeBook(
                        ctx(side: side, score: score, velocity: velocity), seed: 5)
                    XCTAssertGreaterThan(book.nbbo.ask, book.nbbo.bid,
                                         "Crossed at score \(score) velocity \(velocity)")
                    XCTAssertGreaterThan(book.nbbo.bid, 0)
                    XCTAssertTrue(book.mark.isFinite)
                    XCTAssertEqual(book.quotes.count, 5)
                }
            }
        }
    }

    /// The headline behavior of the whole feature: a divided crowd must
    /// produce a visibly worse market than a united one.
    func testSpreadWidensWhenTheCrowdFragments() {
        let desk = MarketMakingDesk()
        let united = desk.makeBook(ctx(score: 0.4, volume: 0.8, dispersion: 0.05), seed: 3)
        let split  = desk.makeBook(ctx(score: 0.4, volume: 0.8, dispersion: 0.95), seed: 3)
        XCTAssertGreaterThan(split.nbbo.spreadPct, united.nbbo.spreadPct)
    }

    /// A narrative shock should visibly drain the book, because both the
    /// scalper and the vol desk pull quotes.
    func testShockDrainsLiquidity() {
        let desk = MarketMakingDesk()
        let calm  = desk.makeBook(ctx(velocity: 0.0), seed: 3)
        let shock = desk.makeBook(ctx(velocity: 0.95), seed: 3)

        func totalDepth(_ book: QuoteBook) -> Int {
            book.quotes.reduce(0) { $0 + $1.bidSize + $1.askSize }
        }

        XCTAssertEqual(calm.steppedAway.count, 0, "Nobody should pull out in calm tape")
        XCTAssertGreaterThan(shock.steppedAway.count, 0, "The vol desk must go dark on a shock")
        XCTAssertLessThan(totalDepth(shock), totalDepth(calm),
                          "A shock must remove real size from the book")
    }

    func testBullishCrowdLiftsCallsAndDropsPuts() {
        let desk = MarketMakingDesk()
        let callFlat = desk.makeBook(ctx(side: .call, score: 0), seed: 2)
        let callHot  = desk.makeBook(ctx(side: .call, score: 0.9, volume: 0.9, dispersion: 0.1), seed: 2)
        let putFlat  = desk.makeBook(ctx(side: .put, score: 0), seed: 2)
        let putHot   = desk.makeBook(ctx(side: .put, score: 0.9, volume: 0.9, dispersion: 0.1), seed: 2)

        XCTAssertGreaterThan(callHot.mark, callFlat.mark, "Bullish crowd should lift Calls")
        XCTAssertLessThan(putHot.mark, putFlat.mark, "The same crowd should drop Puts")
    }

    func testDeskIsDeterministicForAFixedSeed() {
        let desk = MarketMakingDesk()
        let a = desk.makeBook(ctx(score: 0.3, velocity: 0.2), seed: 77)
        let b = desk.makeBook(ctx(score: 0.3, velocity: 0.2), seed: 77)
        XCTAssertEqual(a.nbbo, b.nbbo)
        XCTAssertEqual(a.quotes, b.quotes)
    }

    func testDefaultSeedDerivesFromContractId() {
        // No explicit seed: the contract id must still make it reproducible.
        let desk = MarketMakingDesk()
        let a = desk.makeBook(ctx(score: 0.3))
        let b = desk.makeBook(ctx(score: 0.3))
        XCTAssertEqual(a.nbbo, b.nbbo)
    }

    // MARK: - Quote value type

    func testQuote_imbalanceReflectsWhereSizeSits() {
        XCTAssertEqual(Quote(bid: 9, ask: 10, bidSize: 10, askSize: 0).imbalance, 1.0, accuracy: 0.001)
        XCTAssertEqual(Quote(bid: 9, ask: 10, bidSize: 0, askSize: 10).imbalance, -1.0, accuracy: 0.001)
        XCTAssertEqual(Quote(bid: 9, ask: 10, bidSize: 5, askSize: 5).imbalance, 0.0, accuracy: 0.001)
        XCTAssertEqual(Quote(bid: 9, ask: 10, bidSize: 0, askSize: 0).imbalance, 0.0, accuracy: 0.001)
    }

    func testQuote_executionPriceUsesTheCorrectSide() {
        let q = Quote(bid: 9.40, ask: 9.60, bidSize: 5, askSize: 5)
        XCTAssertEqual(q.executionPrice(isBuy: true), 9.60, accuracy: 0.001)
        XCTAssertEqual(q.executionPrice(isBuy: false), 9.40, accuracy: 0.001)
        XCTAssertEqual(q.mid, 9.50, accuracy: 0.001)
    }

    func testQuote_liquidityGradeTracksSpread() {
        XCTAssertEqual(Quote(bid: 9.95, ask: 10.05, bidSize: 1, askSize: 1).liquidityGrade, .deep)
        XCTAssertEqual(Quote(bid: 9.80, ask: 10.20, bidSize: 1, askSize: 1).liquidityGrade, .healthy)
        XCTAssertEqual(Quote(bid: 9.60, ask: 10.40, bidSize: 1, askSize: 1).liquidityGrade, .thin)
        XCTAssertEqual(Quote(bid: 8.00, ask: 12.00, bidSize: 1, askSize: 1).liquidityGrade, .fractured)
    }

    // MARK: - Desk summary

    func testDeskSummary_averagesAcrossTheChain() {
        let desk = MarketMakingDesk()
        let books = [
            desk.makeBook(ctx(side: .call, score: 0.5), seed: 1),
            desk.makeBook(ctx(side: .put, score: 0.5), seed: 2)
        ]
        let summary = DeskSummary.build(movieId: "m1", books: books,
                                        pulse: SentimentPulse(score: 0.5))
        XCTAssertEqual(summary.contractsQuoted, 2)
        XCTAssertGreaterThan(summary.averageSpreadPct, 0)
        XCTAssertFalse(summary.headline.isEmpty)
    }

    func testDeskSummary_handlesAnEmptyChain() {
        let summary = DeskSummary.build(movieId: "m1", books: [], pulse: .flat)
        XCTAssertEqual(summary.contractsQuoted, 0)
        XCTAssertEqual(summary.averageSpreadPct, 0)
        XCTAssertFalse(summary.headline.isEmpty)
    }
}
