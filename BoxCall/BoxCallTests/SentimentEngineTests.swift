import XCTest
@testable import BoxCall

/// The sentiment math is the input to every quote on the desk, so it is
/// tested directly rather than through the market.
final class SentimentModelTests: XCTestCase {

    // MARK: - Pulse value type

    func testPulse_clampsEveryFieldIntoRange() {
        let p = SentimentPulse(score: 5, velocity: -9, volume: 12, dispersion: -3)
        XCTAssertEqual(p.score, 1)
        XCTAssertEqual(p.velocity, -1)
        XCTAssertEqual(p.volume, 1)
        XCTAssertEqual(p.dispersion, 0)
    }

    func testPulse_rejectsNonFiniteInput() {
        let p = SentimentPulse(score: .nan, velocity: .infinity,
                               volume: .nan, dispersion: -.infinity)
        XCTAssertEqual(p.score, 0)
        XCTAssertEqual(p.velocity, 0)
        XCTAssertEqual(p.volume, 0)
        XCTAssertEqual(p.dispersion, 0)
    }

    /// The single most important sign rule in the system: a bullish
    /// crowd is a tailwind for Calls and a headwind for Puts.
    func testPulse_directionalFlipsForPuts() {
        let p = SentimentPulse(score: 0.6, velocity: 0.4)
        XCTAssertEqual(p.directional(for: .call), 0.6, accuracy: 0.001)
        XCTAssertEqual(p.directional(for: .put), -0.6, accuracy: 0.001)
        XCTAssertEqual(p.directionalVelocity(for: .call), 0.4, accuracy: 0.001)
        XCTAssertEqual(p.directionalVelocity(for: .put), -0.4, accuracy: 0.001)
    }

    func testPulse_moodBuckets() {
        XCTAssertEqual(SentimentPulse(score: 0.9).mood, .euphoric)
        XCTAssertEqual(SentimentPulse(score: 0.3).mood, .bullish)
        XCTAssertEqual(SentimentPulse(score: 0.0).mood, .mixed)
        XCTAssertEqual(SentimentPulse(score: -0.3).mood, .bearish)
        XCTAssertEqual(SentimentPulse(score: -0.9).mood, .panicked)
    }

    func testPulse_confidenceFallsWhenTheRoomIsSplit() {
        let united = SentimentPulse(score: 0.5, volume: 0.9, dispersion: 0.05)
        let split  = SentimentPulse(score: 0.5, volume: 0.9, dispersion: 0.95)
        XCTAssertGreaterThan(united.confidence, split.confidence)
    }

    func testPulse_shockAndConvictionFlags() {
        XCTAssertTrue(SentimentPulse(velocity: 0.8).isShock)
        XCTAssertFalse(SentimentPulse(velocity: 0.2).isShock)
        XCTAssertTrue(SentimentPulse(volume: 0.8, dispersion: 0.1).isConviction)
        XCTAssertFalse(SentimentPulse(volume: 0.2, dispersion: 0.1).isConviction)
        XCTAssertFalse(SentimentPulse(volume: 0.8, dispersion: 0.9).isConviction)
    }

    // MARK: - Aggregation

    func testAggregate_emptyWindowIsQuietNotBullish() {
        let agg = SentimentModel.aggregate(impacts: [])
        XCTAssertEqual(agg.mean, 0)
        XCTAssertEqual(agg.volume, 0)
    }

    func testAggregate_unanimousCrowdHasNoDispersion() {
        let agg = SentimentModel.aggregate(impacts: [0.5, 0.5, 0.5, 0.5])
        XCTAssertEqual(agg.mean, 0.5, accuracy: 0.001)
        XCTAssertEqual(agg.dispersion, 0, accuracy: 0.001)
    }

    /// A room shouting in both directions nets to neutral but must read
    /// as highly dispersed — that is what widens spreads.
    func testAggregate_splitCrowdIsNeutralButDispersed() {
        let agg = SentimentModel.aggregate(impacts: [1, -1, 1, -1])
        XCTAssertEqual(agg.mean, 0, accuracy: 0.001)
        XCTAssertGreaterThan(agg.dispersion, 0.9)
    }

    func testAggregate_volumeScalesWithItemCount() {
        let quiet = SentimentModel.aggregate(impacts: [0.5], loudAt: 10)
        let loud  = SentimentModel.aggregate(impacts: Array(repeating: 0.5, count: 10), loudAt: 10)
        XCTAssertLessThan(quiet.volume, loud.volume)
        XCTAssertEqual(loud.volume, 1.0, accuracy: 0.001)
    }

    func testAggregate_volumeSaturates() {
        let agg = SentimentModel.aggregate(impacts: Array(repeating: 0.2, count: 500), loudAt: 10)
        XCTAssertEqual(agg.volume, 1.0, accuracy: 0.001)
    }

    // MARK: - Flow

    func testFlowScore_callBuyingIsBullish() {
        XCTAssertGreaterThan(SentimentModel.flowScore(callVolume: 100, putVolume: 10), 0)
        XCTAssertLessThan(SentimentModel.flowScore(callVolume: 10, putVolume: 100), 0)
        XCTAssertEqual(SentimentModel.flowScore(callVolume: 50, putVolume: 50), 0, accuracy: 0.001)
        XCTAssertEqual(SentimentModel.flowScore(callVolume: 0, putVolume: 0), 0)
    }

    func testFlowScore_isDampedSoOneTradeCannotPinThePulse() {
        // Even a completely one-sided tape stays short of the extreme.
        XCTAssertLessThan(SentimentModel.flowScore(callVolume: 1000, putVolume: 0), 0.75)
    }

    // MARK: - Blending

    func testBlend_movesTowardTheTargetWithoutTeleporting() {
        let start = SentimentPulse(score: 0)
        let next = SentimentModel.blend(previous: start, targetScore: 1.0,
                                        targetVolume: 0.5, targetDispersion: 0.3,
                                        elapsed: 3, halfLife: 90)
        XCTAssertGreaterThan(next.score, 0)
        XCTAssertLessThan(next.score, 0.2, "One tick must not jump to the target")
    }

    func testBlend_convergesOnTheTargetOverManyTicks() {
        var pulse = SentimentPulse(score: 0)
        for _ in 0..<400 {
            pulse = SentimentModel.blend(previous: pulse, targetScore: 0.8,
                                         targetVolume: 0.6, targetDispersion: 0.2,
                                         elapsed: 3, halfLife: 90)
        }
        XCTAssertEqual(pulse.score, 0.8, accuracy: 0.02)
        XCTAssertEqual(pulse.volume, 0.6, accuracy: 0.02)
        XCTAssertEqual(pulse.dispersion, 0.2, accuracy: 0.02)
    }

    /// A fast move must register as velocity, because velocity is what
    /// makes the scalper and vol desk pull their quotes.
    func testBlend_registersVelocityOnAFastMove() {
        let calm = SentimentModel.blend(previous: SentimentPulse(score: 0),
                                        targetScore: 0.1,
                                        targetVolume: 0.5, targetDispersion: 0.3,
                                        elapsed: 30, halfLife: 90)
        // Velocity is smoothed against the previous reading, so a shock
        // builds over a couple of fast ticks rather than one.
        var sudden = SentimentPulse(score: 0)
        for _ in 0..<2 {
            sudden = SentimentModel.blend(previous: sudden, targetScore: 1.0,
                                          targetVolume: 0.5, targetDispersion: 0.3,
                                          elapsed: 1, halfLife: 3)
        }
        XCTAssertGreaterThan(sudden.velocity, calm.velocity)
        XCTAssertTrue(sudden.isShock, "A near-instant flip should read as a shock")
    }

    func testBlend_velocitySignFollowsDirection() {
        let up = SentimentModel.blend(previous: SentimentPulse(score: 0),
                                      targetScore: 1, targetVolume: 0.5,
                                      targetDispersion: 0.3, elapsed: 1, halfLife: 3)
        let down = SentimentModel.blend(previous: SentimentPulse(score: 0),
                                        targetScore: -1, targetVolume: 0.5,
                                        targetDispersion: 0.3, elapsed: 1, halfLife: 3)
        XCTAssertGreaterThan(up.velocity, 0)
        XCTAssertLessThan(down.velocity, 0)
    }

    func testBlend_toleratesAZeroElapsedInterval() {
        let next = SentimentModel.blend(previous: SentimentPulse(score: 0.4),
                                        targetScore: -0.4, targetVolume: 0.5,
                                        targetDispersion: 0.3, elapsed: 0)
        XCTAssertTrue(next.score.isFinite)
        XCTAssertTrue(next.velocity.isFinite)
        XCTAssertEqual(next.score, 0.4, accuracy: 0.01, "No elapsed time, no movement")
    }

    func testDecay_relaxesTowardNeutral() {
        var pulse = SentimentPulse(score: 0.9, volume: 0.9, dispersion: 0.1)
        for _ in 0..<300 {
            pulse = SentimentModel.decayed(pulse, elapsed: 3, halfLife: 90)
        }
        XCTAssertEqual(pulse.score, 0, accuracy: 0.02)
        XCTAssertEqual(pulse.volume, 0, accuracy: 0.02)
    }

    // MARK: - Baseline from a real social capture

    func testBaseline_rescalesConsensusAdjustmentToFullRange() {
        let bullish = SocialSignal(youtubeTrailerViews7d: 60_000_000,
                                   youtubeLikeRatio: 0.98,
                                   xMentions24h: 200_000,
                                   xSentiment: 0.9,
                                   capturedAt: Date())
        let bearish = SocialSignal(youtubeTrailerViews7d: 100_000,
                                   youtubeLikeRatio: 0.4,
                                   xMentions24h: 200,
                                   xSentiment: -0.9,
                                   capturedAt: Date())
        let up = SentimentModel.baseline(from: bullish)
        let down = SentimentModel.baseline(from: bearish)
        XCTAssertGreaterThan(up, 0.5)
        XCTAssertLessThan(down, -0.5)
        XCTAssertLessThanOrEqual(up, 1.0)
        XCTAssertGreaterThanOrEqual(down, -1.0)
    }
}

// MARK: - Live engine

@MainActor
final class SentimentEngineTests: XCTestCase {

    /// The shared engine carries state between tests, so every case
    /// works on its own movie id.
    private func uniqueMovieId(_ fn: String = #function) -> String {
        "test_\(fn)_\(UUID().uuidString)"
    }

    func testUnknownMovieReadsFlat() {
        let pulse = SentimentEngine.shared.pulse(for: uniqueMovieId())
        XCTAssertEqual(pulse.score, 0)
        XCTAssertEqual(pulse.mood, .mixed)
    }

    func testCallFlowPushesSentimentBullish() {
        let engine = SentimentEngine.shared
        let id = uniqueMovieId()
        var rng = SeededGenerator(seed: 1)
        // Enough real flow to dominate any ambient chatter the tick
        // generator adds along the way.
        for _ in 0..<15 {
            engine.recordFlow(movieId: id, side: .call, quantity: 20)
        }
        for _ in 0..<20 {
            engine.tick(movieIds: [id], now: Date(), rng: &rng)
        }
        XCTAssertGreaterThan(engine.pulse(for: id).score, 0)
    }

    func testPutFlowPushesSentimentBearish() {
        let engine = SentimentEngine.shared
        let id = uniqueMovieId()
        var rng = SeededGenerator(seed: 1)
        for _ in 0..<15 {
            engine.recordFlow(movieId: id, side: .put, quantity: 20)
        }
        for _ in 0..<20 {
            engine.tick(movieIds: [id], now: Date(), rng: &rng)
        }
        XCTAssertLessThan(engine.pulse(for: id).score, 0)
    }

    func testEventsAreRecordedAndAttributedToTheRightMovie() {
        let engine = SentimentEngine.shared
        let mine = uniqueMovieId()
        let other = uniqueMovieId()
        engine.recordHeadline(movieId: mine, headline: "Reshoots confirmed", magnitude: -0.2)
        engine.recordHotTake(movieId: other, side: .call, handle: "someone")

        let events = engine.chatter(for: mine)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, .headline)
        XCTAssertLessThan(events.first?.impact ?? 0, 0)
        XCTAssertTrue(engine.chatter(for: other).allSatisfy { $0.movieId == other })
    }

    func testReviewRatingMapsToSignedImpact() {
        let engine = SentimentEngine.shared
        let rave = uniqueMovieId()
        let pan = uniqueMovieId()
        engine.recordReview(movieId: rave, rating: 5, handle: "critic")
        engine.recordReview(movieId: pan, rating: 1, handle: "critic")
        XCTAssertGreaterThan(engine.chatter(for: rave).first?.impact ?? 0, 0)
        XCTAssertLessThan(engine.chatter(for: pan).first?.impact ?? 0, 0)
    }

    func testHistoryAccumulatesOnTick() {
        let engine = SentimentEngine.shared
        let id = uniqueMovieId()
        var rng = SeededGenerator(seed: 2)
        for _ in 0..<5 {
            engine.tick(movieIds: [id], now: Date(), rng: &rng)
        }
        XCTAssertGreaterThanOrEqual(engine.scoreHistory(for: id).count, 5)
    }

    /// However violent the inputs, the published pulse has to stay
    /// inside the range the agents assume. They do no clamping of their
    /// own, so a leak here would corrupt every quote on the desk.
    func testPulseStaysInRangeUnderExtremeInput() {
        let engine = SentimentEngine.shared
        let id = uniqueMovieId()
        var rng = SeededGenerator(seed: 31)
        for _ in 0..<40 {
            engine.recordFlow(movieId: id, side: .call, quantity: 10_000)
            engine.recordHeadline(movieId: id, headline: "Blowout", magnitude: 99)
            engine.recordReview(movieId: id, rating: 5, handle: "critic")
        }
        for _ in 0..<50 {
            engine.tick(movieIds: [id], now: Date(), rng: &rng)
            let p = engine.pulse(for: id)
            XCTAssertTrue((-1...1).contains(p.score))
            XCTAssertTrue((-1...1).contains(p.velocity))
            XCTAssertTrue((0...1).contains(p.volume))
            XCTAssertTrue((0...1).contains(p.dispersion))
            XCTAssertTrue((0...1).contains(p.confidence))
        }
    }

    /// Ticking a movie nobody is talking about must not invent an opinion.
    func testQuietMovieStaysNearNeutral() {
        let engine = SentimentEngine.shared
        let id = uniqueMovieId()
        var rng = SeededGenerator(seed: 17)
        for _ in 0..<10 {
            engine.tick(movieIds: [id], now: Date(), rng: &rng)
        }
        XCTAssertLessThan(abs(engine.pulse(for: id).score), 0.3)
    }

    func testMoversByHeatRanksByAbsoluteScore() {
        let engine = SentimentEngine.shared
        let hot = uniqueMovieId()
        var rng = SeededGenerator(seed: 9)
        for _ in 0..<10 {
            engine.recordFlow(movieId: hot, side: .call, quantity: 40)
        }
        for _ in 0..<30 {
            engine.tick(movieIds: [hot], now: Date(), rng: &rng)
        }
        let movers = engine.moversByHeat(limit: 3)
        XCTAssertFalse(movers.isEmpty)
        // Ranking is by magnitude, so the list is monotonically ordered.
        for i in 1..<max(1, movers.count) {
            XCTAssertGreaterThanOrEqual(abs(movers[i - 1].pulse.score),
                                        abs(movers[i].pulse.score))
        }
    }
}
