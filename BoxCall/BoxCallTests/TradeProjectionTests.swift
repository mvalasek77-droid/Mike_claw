import XCTest
@testable import BoxCall

final class TradeProjectionTests: XCTestCase {

    private let now = Date()

    private func projection(low: Double, high: Double,
                            ageDays: Double = 0,
                            published: Bool = true) -> TradeProjection {
        TradeProjection(lowMillions: low, highMillions: high,
                        source: "Test",
                        asOf: now.addingTimeInterval(-ageDays * 86_400),
                        isPublished: published)
    }

    // MARK: - Range handling

    func testMidpointAndWidth() {
        let p = projection(low: 260, high: 300)
        XCTAssertEqual(p.midpointMillions, 280, accuracy: 0.001)
        XCTAssertEqual(p.halfWidthMillions, 20, accuracy: 0.001)
        XCTAssertEqual(p.rangeRatio, 20.0 / 280.0, accuracy: 0.0001)
    }

    func testRangeHandedOverBackwardsIsNormalized() {
        let p = projection(low: 300, high: 260)
        XCTAssertEqual(p.lowMillions, 260, accuracy: 0.001)
        XCTAssertEqual(p.highMillions, 300, accuracy: 0.001)
        XCTAssertGreaterThan(p.halfWidthMillions, 0)
    }

    func testAPointEstimateHasNoWidth() {
        let p = projection(low: 100, high: 100)
        XCTAssertEqual(p.rangeRatio, 0, accuracy: 0.0001)
        XCTAssertEqual(p.midpointMillions, 100, accuracy: 0.001)
    }

    // MARK: - Implied volatility from disagreement

    /// The real information in a forecast range is its width. A title
    /// the analysts agree on should price tighter contracts than one
    /// they are split over.
    func testWiderRangesImplyHigherVolatility() {
        let agreed = projection(low: 260, high: 300)      // tentpole, locked in
        let contested = projection(low: 45, high: 90)     // analysts split
        XCTAssertLessThan(agreed.impliedVolPct, contested.impliedVolPct)
    }

    func testImpliedVolIsBounded() {
        XCTAssertGreaterThanOrEqual(projection(low: 100, high: 100).impliedVolPct, 20)
        XCTAssertLessThanOrEqual(projection(low: 1, high: 500).impliedVolPct, 70)
    }

    func testImpliedVolOfARealTentpoleIsReasonable() {
        // Avengers-shaped: $260-300M. Tight band on a huge number.
        let iv = projection(low: 260, high: 300).impliedVolPct
        XCTAssertGreaterThan(iv, 25)
        XCTAssertLessThan(iv, 40)
    }

    // MARK: - Confidence decay

    func testFreshPublishedProjectionIsFullyTrusted() {
        XCTAssertEqual(projection(low: 100, high: 130).confidence(asOf: now),
                       1.0, accuracy: 0.01)
    }

    func testConfidenceHalvesEveryTwoMonths() {
        let p = projection(low: 100, high: 130, ageDays: 60)
        XCTAssertEqual(p.confidence(asOf: now), 0.5, accuracy: 0.02)
    }

    func testStaleProjectionsFade() {
        let fresh = projection(low: 100, high: 130, ageDays: 0)
        let old = projection(low: 100, high: 130, ageDays: 180)
        XCTAssertGreaterThan(fresh.confidence(asOf: now), old.confidence(asOf: now))
        XCTAssertLessThan(old.confidence(asOf: now), 0.2)
    }

    /// A number the app derived must never carry the authority of one a
    /// trade actually printed.
    func testDerivedProjectionsAreCappedBelowPublishedOnes() {
        let derived = projection(low: 100, high: 130, published: false)
        let published = projection(low: 100, high: 130, published: true)
        XCTAssertLessThanOrEqual(derived.confidence(asOf: now), 0.5)
        XCTAssertGreaterThan(published.confidence(asOf: now),
                             derived.confidence(asOf: now))
    }

    func testDerivedFactoryIsFlaggedAsUnpublished() {
        let p = TradeProjection.derived(centerMillions: 50)
        XCTAssertFalse(p.isPublished)
        XCTAssertEqual(p.midpointMillions, 50, accuracy: 0.001)
        XCTAssertTrue(p.attribution.contains("estimated"))
        XCTAssertFalse(p.attribution.contains("projected"))
    }

    func testAttributionNamesTheSource() {
        let p = TradeProjection(lowMillions: 260, highMillions: 300,
                                source: "Pre-sale tracking consensus",
                                asOf: now, isPublished: true)
        XCTAssertTrue(p.attribution.contains("260"))
        XCTAssertTrue(p.attribution.contains("300"))
        XCTAssertTrue(p.attribution.contains("Pre-sale tracking consensus"))
        XCTAssertTrue(p.attribution.contains("projected"))
    }
}

// MARK: - Tracking source

final class TradeProjectionTrackingSourceTests: XCTestCase {

    private func movie(projection: TradeProjection?,
                       fallbackOpening: Double = 40,
                       fallbackIV: Double = 50) -> Movie {
        Movie(id: "m1", title: "Test Film", studio: "Studio",
              releaseDate: Date().addingTimeInterval(30 * 86_400),
              posterEmoji: "🎬", tagline: "",
              consensusOpeningMillions: fallbackOpening,
              impliedVolPct: fallbackIV, genre: "Drama",
              tradeProjection: projection)
    }

    func testNoProjectionFallsThroughToTheNextSource() async {
        let source = TradeProjectionTrackingSource()
        let result = await source.tracking(for: movie(projection: nil))
        XCTAssertNil(result, "Must fall through so the composite can try the next source")
    }

    func testFreshProjectionDrivesTheNumber() async {
        let p = TradeProjection(lowMillions: 260, highMillions: 300,
                                source: "Trades", asOf: Date(), isPublished: true)
        let result = await TradeProjectionTrackingSource()
            .tracking(for: movie(projection: p, fallbackOpening: 40))
        let tracking = try? XCTUnwrap(result)
        XCTAssertEqual(tracking?.openingWeekendMillions ?? 0, 280, accuracy: 5,
                       "A fresh published range should dominate the app's own estimate")
    }

    /// An old projection should hand the number back rather than keep
    /// steering a movie the week it opens.
    func testAgingProjectionBlendsBackTowardTheAppEstimate() async {
        let source = TradeProjectionTrackingSource()
        let fresh = TradeProjection(lowMillions: 200, highMillions: 200,
                                    source: "Trades", asOf: Date(),
                                    isPublished: true)
        let stale = TradeProjection(lowMillions: 200, highMillions: 200,
                                    source: "Trades",
                                    asOf: Date().addingTimeInterval(-90 * 86_400),
                                    isPublished: true)
        let freshResult = await source.tracking(for: movie(projection: fresh, fallbackOpening: 40))
        let staleResult = await source.tracking(for: movie(projection: stale, fallbackOpening: 40))
        XCTAssertNotNil(freshResult)
        XCTAssertNotNil(staleResult)
        XCTAssertGreaterThan(freshResult?.openingWeekendMillions ?? 0,
                             staleResult?.openingWeekendMillions ?? 0)
    }

    func testVeryStaleProjectionIsAbandoned() async {
        let ancient = TradeProjection(lowMillions: 200, highMillions: 220,
                                      source: "Trades",
                                      asOf: Date().addingTimeInterval(-365 * 86_400),
                                      isPublished: true)
        let result = await TradeProjectionTrackingSource()
            .tracking(for: movie(projection: ancient))
        XCTAssertNil(result, "A year-old projection should stop leading entirely")
    }

    func testDisagreementCarriesThroughToImpliedVol() async {
        let source = TradeProjectionTrackingSource()
        let agreed = TradeProjection(lowMillions: 260, highMillions: 300,
                                     source: "Trades", asOf: Date(), isPublished: true)
        let split = TradeProjection(lowMillions: 45, highMillions: 90,
                                    source: "Trades", asOf: Date(), isPublished: true)
        let a = await source.tracking(for: movie(projection: agreed))
        let s = await source.tracking(for: movie(projection: split))
        XCTAssertLessThan(a?.impliedVolPct ?? 99, s?.impliedVolPct ?? 0)
    }

    func testOutputIsAlwaysSane() async {
        let source = TradeProjectionTrackingSource()
        for (low, high) in [(0.0, 0.0), (1.0, 1000.0), (5.0, 5.0)] {
            let p = TradeProjection(lowMillions: low, highMillions: high,
                                    source: "Trades", asOf: Date(), isPublished: true)
            guard let t = await source.tracking(for: movie(projection: p)) else { continue }
            XCTAssertGreaterThan(t.openingWeekendMillions, 0)
            XCTAssertGreaterThanOrEqual(t.impliedVolPct, 15)
            XCTAssertTrue(t.openingWeekendMillions.isFinite)
        }
    }
}

// MARK: - The shipped slate

final class BuiltInSeedTests: XCTestCase {

    private var seed: [Movie] { MockMovieProvider.builtInSeed() }

    /// The bug that prompted this pass: Clayface was listed as opening
    /// within days when the studio had moved it to late October.
    func testEveryTitleOpensInTheFuture() {
        for movie in seed {
            XCTAssertGreaterThanOrEqual(
                movie.daysToRelease, 0,
                "\(movie.title) is dated in the past — a contract on it can never settle")
        }
    }

    func testNoDuplicateIdsOrTitles() {
        XCTAssertEqual(Set(seed.map(\.id)).count, seed.count)
        XCTAssertEqual(Set(seed.map(\.title)).count, seed.count)
    }

    func testEveryTitleIsUsableAsAMarket() {
        for movie in seed {
            XCTAssertFalse(movie.title.isEmpty)
            XCTAssertFalse(movie.studio.isEmpty)
            XCTAssertGreaterThan(movie.consensusOpeningMillions, 0,
                                 "\(movie.title) has no number to strike against")
            XCTAssertGreaterThan(movie.impliedVolPct, 0)
            XCTAssertFalse(movie.isSettled)
        }
    }

    /// A projection is either something a trade published or something
    /// the app derived, and the flag has to be right — the UI shows the
    /// source name next to the number.
    func testPublishedProjectionsCarryASource() {
        for movie in seed {
            guard let p = movie.tradeProjection else { continue }
            XCTAssertFalse(p.source.isEmpty, "\(movie.title) projection has no attribution")
            XCTAssertGreaterThan(p.lowMillions, 0)
            XCTAssertGreaterThanOrEqual(p.highMillions, p.lowMillions)
        }
    }

    func testProjectionsAreBroadlyConsistentWithTheBaseEstimate() {
        for movie in seed {
            guard let p = movie.tradeProjection, p.isPublished else { continue }
            // The seeded estimate should sit inside the published band,
            // or the two are telling the user different stories.
            XCTAssertGreaterThanOrEqual(movie.consensusOpeningMillions, p.lowMillions * 0.8,
                                        "\(movie.title): estimate far below the trade range")
            XCTAssertLessThanOrEqual(movie.consensusOpeningMillions, p.highMillions * 1.2,
                                     "\(movie.title): estimate far above the trade range")
        }
    }

    func testSlateIsOrderedByReleaseDate() {
        let dates = seed.map(\.releaseDate)
        XCTAssertEqual(dates, dates.sorted(),
                       "The board reads soonest-first; the seed should already be in that order")
    }
}
