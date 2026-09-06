import XCTest
@testable import BoxCall

/// Every agent is a pure function of its context plus a seeded random
/// stream, so each of these tests pins exact behavior rather than
/// asserting that "something moved".
final class MarketMakingAgentTests: XCTestCase {

    // MARK: - Fixtures

    private func contract(side: ContractSide = .call,
                          strike: Double = 100,
                          base: Double = 10) -> Contract {
        Contract(id: "m1_\(side.rawValue)_\(Int(strike))",
                 movieId: "m1", side: side, strikeMillions: strike,
                 basePremium: base, premium: base,
                 multiplier: 1, openInterest: 100)
    }

    private func ctx(side: ContractSide = .call,
                     fair: Double = 10,
                     score: Double = 0,
                     velocity: Double = 0,
                     volume: Double = 0.5,
                     dispersion: Double = 0.3,
                     level: SRLevel? = nil,
                     dte: Int = 30,
                     inventory: Double = 0) -> QuoteContext {
        QuoteContext(
            contract: contract(side: side),
            fairValue: fair,
            pulse: SentimentPulse(score: score, velocity: velocity,
                                  volume: volume, dispersion: dispersion),
            level: level,
            daysToRelease: dte,
            inventory: inventory
        )
    }

    private func rng(_ seed: UInt64 = 42) -> SeededGenerator { SeededGenerator(seed: seed) }

    // MARK: - Universal invariants

    /// No agent, under any sentiment, may publish a crossed, negative,
    /// or zero-width market. Everything downstream depends on this.
    func testAllAgents_neverPublishInvalidMarkets() {
        let agents = AgentRoster.standard()
        let scores: [Double] = [-1, -0.7, -0.3, 0, 0.3, 0.7, 1]
        let velocities: [Double] = [-1, -0.6, 0, 0.6, 1]
        let dispersions: [Double] = [0, 0.5, 1]

        for agent in agents {
            for s in scores {
                for v in velocities {
                    for d in dispersions {
                        for side in ContractSide.allCases {
                            var g = rng(7)
                            let q = agent.quote(
                                ctx(side: side, score: s, velocity: v, dispersion: d),
                                rng: &g
                            )
                            XCTAssertGreaterThan(
                                q.ask, q.bid,
                                "\(agent.name) crossed at score \(s) vel \(v) disp \(d)")
                            XCTAssertGreaterThan(
                                q.bid, 0,
                                "\(agent.name) published a non-positive bid")
                            XCTAssertGreaterThanOrEqual(
                                q.quote.spread, 0.02 - 0.0001,
                                "\(agent.name) published a sub-minimum spread")
                            XCTAssertFalse(q.rationale.isEmpty)
                        }
                    }
                }
            }
        }
    }

    /// Same context plus same seed must give a byte-identical quote.
    func testAllAgents_areDeterministicForAFixedSeed() {
        for agent in AgentRoster.standard() {
            var a = rng(99), b = rng(99)
            let first = agent.quote(ctx(score: 0.4, velocity: 0.2), rng: &a)
            let second = agent.quote(ctx(score: 0.4, velocity: 0.2), rng: &b)
            XCTAssertEqual(first.quote, second.quote, "\(agent.name) is not deterministic")
            XCTAssertEqual(first.rationale, second.rationale)
        }
    }

    // MARK: - Momentum

    func testMomentum_raisesCallMarketOnBullishCrowd() {
        let agent = MomentumAgent()
        var a = rng(), b = rng()
        let neutral = agent.quote(ctx(side: .call, score: 0), rng: &a)
        let bullish = agent.quote(ctx(side: .call, score: 0.9, volume: 0.9, dispersion: 0.1), rng: &b)
        XCTAssertGreaterThan(bullish.quote.mid, neutral.quote.mid)
        XCTAssertEqual(bullish.stance, .bidding)
    }

    /// The same bullish crowd must push a Put's market the other way.
    /// This is the single most important sign convention in the system.
    func testMomentum_invertsForPuts() {
        let agent = MomentumAgent()
        var a = rng(), b = rng()
        let neutral = agent.quote(ctx(side: .put, score: 0), rng: &a)
        let bullish = agent.quote(ctx(side: .put, score: 0.9, volume: 0.9, dispersion: 0.1), rng: &b)
        XCTAssertLessThan(bullish.quote.mid, neutral.quote.mid)
        XCTAssertEqual(bullish.stance, .offering)
    }

    func testMomentum_showsMoreSizeOnTheSideItWants() {
        var g = rng()
        let q = MomentumAgent().quote(
            ctx(score: 0.8, volume: 0.9, dispersion: 0.1), rng: &g)
        XCTAssertGreaterThan(q.bidSize, q.askSize)
    }

    func testMomentum_ignoresSentimentItHasNoConfidenceIn() {
        let agent = MomentumAgent()
        var loud = rng(3), quiet = rng(3)
        // Same score, but one reading is loud and united and the other
        // is a whisper from a split room.
        let confident = agent.quote(
            ctx(score: 0.8, volume: 0.95, dispersion: 0.05), rng: &loud)
        let unsure = agent.quote(
            ctx(score: 0.8, volume: 0.05, dispersion: 0.95), rng: &quiet)
        XCTAssertGreaterThan(confident.quote.mid, unsure.quote.mid)
    }

    // MARK: - Contrarian

    func testContrarian_staysPassiveInsideItsBand() {
        var g = rng()
        let q = ContrarianAgent().quote(ctx(score: 0.2), rng: &g)
        XCTAssertEqual(q.stance, .balanced)
        XCTAssertEqual(q.bidSize, q.askSize)
    }

    func testContrarian_offersIntoEuphoria() {
        let agent = ContrarianAgent()
        var a = rng(), b = rng()
        let calm = agent.quote(ctx(score: 0), rng: &a)
        let euphoric = agent.quote(ctx(score: 0.95), rng: &b)
        XCTAssertEqual(euphoric.stance, .offering)
        XCTAssertLessThan(euphoric.quote.mid, calm.quote.mid)
        XCTAssertGreaterThan(euphoric.askSize, euphoric.bidSize)
    }

    func testContrarian_bidsIntoPanic() {
        let agent = ContrarianAgent()
        var a = rng(), b = rng()
        let calm = agent.quote(ctx(score: 0), rng: &a)
        let panicked = agent.quote(ctx(score: -0.95), rng: &b)
        XCTAssertEqual(panicked.stance, .bidding)
        XCTAssertGreaterThan(panicked.quote.mid, calm.quote.mid)
        XCTAssertGreaterThan(panicked.bidSize, panicked.askSize)
    }

    /// Momentum and contrarian must genuinely oppose each other at an
    /// extreme — that opposition is what caps runaway prices.
    func testMomentumAndContrarian_opposeAtExtremes() {
        var a = rng(11), b = rng(11)
        let extreme = ctx(score: 0.95, volume: 0.9, dispersion: 0.1)
        let momentum = MomentumAgent().quote(extreme, rng: &a)
        let contrarian = ContrarianAgent().quote(extreme, rng: &b)
        XCTAssertGreaterThan(momentum.quote.mid, contrarian.quote.mid)
        XCTAssertEqual(momentum.stance, .bidding)
        XCTAssertEqual(contrarian.stance, .offering)
    }

    // MARK: - Anchor

    func testAnchor_ignoresSentimentLevel() {
        let agent = AnchorAgent()
        var a = rng(5), b = rng(5)
        let calm = agent.quote(ctx(score: 0, dispersion: 0.3), rng: &a)
        let euphoric = agent.quote(ctx(score: 0.95, dispersion: 0.3), rng: &b)
        XCTAssertEqual(calm.quote.mid, euphoric.quote.mid, accuracy: 0.01,
                       "Anchor must not chase the crowd")
    }

    func testAnchor_widensWithDispersion() {
        let agent = AnchorAgent()
        var a = rng(5), b = rng(5)
        let united = agent.quote(ctx(dispersion: 0.0), rng: &a)
        let split  = agent.quote(ctx(dispersion: 1.0), rng: &b)
        XCTAssertGreaterThan(split.quote.spread, united.quote.spread)
        XCTAssertLessThan(split.bidSize, united.bidSize)
    }

    func testAnchor_pullsTowardSupportResistanceMid() {
        var g = rng()
        let lvl = SRLevel(support: 9.0, resistance: 9.4, mid: 9.2)
        let q = AnchorAgent().quote(ctx(fair: 10, level: lvl), rng: &g)
        // Anchors on the S/R mid but never further than 8% from fair.
        XCTAssertLessThan(q.quote.mid, 10.0)
        XCTAssertGreaterThanOrEqual(q.quote.mid, 9.1)
    }

    func testAnchor_alwaysQuotesBothSides() {
        for d in stride(from: 0.0, through: 1.0, by: 0.25) {
            var g = rng()
            let q = AnchorAgent().quote(ctx(score: 1, velocity: 1, dispersion: d), rng: &g)
            XCTAssertGreaterThan(q.bidSize, 0, "Anchor went dark at dispersion \(d)")
            XCTAssertGreaterThan(q.askSize, 0, "Anchor went dark at dispersion \(d)")
        }
    }

    // MARK: - Velocity scalper

    func testScalper_isTightestAgentInCalmTape() {
        let calm = ctx(score: 0, velocity: 0, dispersion: 0.1)
        var g = rng(21)
        let scalper = VelocityScalperAgent().quote(calm, rng: &g)
        for other in AgentRoster.standard() where other.id != "scalper" {
            var h = rng(21)
            let q = other.quote(calm, rng: &h)
            XCTAssertLessThanOrEqual(scalper.quote.spread, q.quote.spread,
                                     "Scalper should be tightest, \(other.name) was tighter")
        }
    }

    func testScalper_widensWithVelocity() {
        let agent = VelocityScalperAgent()
        var a = rng(4), b = rng(4)
        let calm = agent.quote(ctx(velocity: 0), rng: &a)
        let fast = agent.quote(ctx(velocity: 0.4), rng: &b)
        XCTAssertGreaterThan(fast.quote.spread, calm.quote.spread)
    }

    func testScalper_pullsTheOfferWhenSentimentSpikesUp() {
        var g = rng()
        let q = VelocityScalperAgent().quote(ctx(side: .call, velocity: 0.9), rng: &g)
        XCTAssertEqual(q.stance, .steppingAway)
        XCTAssertEqual(q.askSize, 0, "Should not offer into a spike it would be run over on")
        XCTAssertGreaterThan(q.bidSize, 0)
    }

    func testScalper_pullsTheBidWhenSentimentCollapses() {
        var g = rng()
        let q = VelocityScalperAgent().quote(ctx(side: .call, velocity: -0.9), rng: &g)
        XCTAssertEqual(q.stance, .steppingAway)
        XCTAssertEqual(q.bidSize, 0)
        XCTAssertGreaterThan(q.askSize, 0)
    }

    /// A spike is directional: the side it burns flips for Puts.
    func testScalper_shockSideInvertsForPuts() {
        var g = rng()
        let q = VelocityScalperAgent().quote(ctx(side: .put, velocity: 0.9), rng: &g)
        XCTAssertEqual(q.bidSize, 0, "Rising crowd sentiment burns the Put bid")
        XCTAssertGreaterThan(q.askSize, 0)
    }

    // MARK: - Vol breaker

    func testVolBreaker_hasNoDirectionalOpinion() {
        let agent = VolBreakerAgent()
        var a = rng(8), b = rng(8)
        let bull = agent.quote(ctx(score: 0.9, dispersion: 0.3), rng: &a)
        let bear = agent.quote(ctx(score: -0.9, dispersion: 0.3), rng: &b)
        XCTAssertEqual(bull.quote.mid, bear.quote.mid, accuracy: 0.01)
    }

    func testVolBreaker_widensAndShrinksSizeWithDispersion() {
        let agent = VolBreakerAgent()
        var a = rng(8), b = rng(8)
        let united = agent.quote(ctx(dispersion: 0.05), rng: &a)
        let split  = agent.quote(ctx(dispersion: 0.95), rng: &b)
        XCTAssertGreaterThan(split.quote.spread, united.quote.spread)
        XCTAssertLessThan(split.bidSize, united.bidSize)
    }

    func testVolBreaker_goesDarkOnShock() {
        var g = rng()
        let q = VolBreakerAgent().quote(ctx(velocity: 0.9), rng: &g)
        XCTAssertEqual(q.stance, .steppingAway)
        XCTAssertFalse(q.isQuoting)
        XCTAssertEqual(q.bidSize, 0)
        XCTAssertEqual(q.askSize, 0)
    }

    // MARK: - Inventory

    func testInventorySkew_shadesQuotesDownWhenLong() {
        let agent = MomentumAgent()
        var a = rng(6), b = rng(6)
        let flat = agent.quote(ctx(inventory: 0), rng: &a)
        let long = agent.quote(ctx(inventory: 400), rng: &b)
        XCTAssertLessThan(long.quote.mid, flat.quote.mid,
                          "A long desk should shade down to get hit on the offer")
    }

    func testInventorySkew_isBoundedBySaturation() {
        // Inventory pressure saturates, so an absurd position cannot
        // walk the market to zero.
        var a = rng(6), b = rng(6)
        let big = MomentumAgent().quote(ctx(inventory: 10_000), rng: &a)
        let huge = MomentumAgent().quote(ctx(inventory: 1_000_000), rng: &b)
        XCTAssertEqual(big.quote.mid, huge.quote.mid, accuracy: 0.01)
        XCTAssertGreaterThan(huge.quote.bid, 0)
    }

    // MARK: - Expiry

    func testExpiryPressure_widensEveryAgentAsOpeningNightNears() {
        for agent in AgentRoster.standard() {
            var a = rng(13), b = rng(13)
            let far  = agent.quote(ctx(dte: 60), rng: &a)
            let near = agent.quote(ctx(dte: 0), rng: &b)
            XCTAssertGreaterThan(near.quote.spread, far.quote.spread,
                                 "\(agent.name) did not widen into expiry")
        }
    }
}
