import XCTest
@testable import BoxCall

final class SocialSignalTests: XCTestCase {

    private let base = SignalBaseline.generic

    // MARK: - Range

    func testAdjustment_clampedTo30Percent() {
        // Absurdly bullish signal — should still cap at +0.30
        let sig = SocialSignal(
            youtubeTrailerViews7d: 500_000_000,
            youtubeEngagementRate: 0.09,
            xMentions24h: 5_000_000,
            xSentiment: 1.0
        )
        let adj = sig.consensusAdjustment(genreBaseline: base)
        XCTAssertLessThanOrEqual(adj, 0.30 + 1e-6)
        XCTAssertGreaterThan(adj, 0.0)
    }

    func testAdjustment_negativeForCratering() {
        let sig = SocialSignal(
            youtubeTrailerViews7d: 0,
            youtubeEngagementRate: 0.001,
            xMentions24h: 0,
            xSentiment: -1.0
        )
        let adj = sig.consensusAdjustment(genreBaseline: base)
        XCTAssertLessThan(adj, 0.0)
        XCTAssertGreaterThanOrEqual(adj, -0.30 - 1e-6)
    }

    func testAdjustment_neutralAtBaseline() {
        let sig = SocialSignal(
            youtubeTrailerViews7d: Int(base.trailerViewsMean),
            youtubeEngagementRate: base.engagementMean,
            xMentions24h: Int(base.mentionsMean),
            xSentiment: 0.0
        )
        let adj = sig.consensusAdjustment(genreBaseline: base)
        XCTAssertLessThan(abs(adj), 0.01)
    }

    // MARK: - Missing data must not be read as zero

    /// The defect this guards: with the X endpoint stubbed, folding its
    /// absence in as "0 mentions, neutral sentiment" put a permanent
    /// bearish drag on every movie — about a third of the model's full
    /// range — purely because a source was unreachable.
    func testMissingSourceDoesNotBias() {
        let youtubeOnly = SocialSignal(
            youtubeTrailerViews7d: Int(base.trailerViewsMean),
            youtubeEngagementRate: base.engagementMean,
            xMentions24h: nil,
            xSentiment: nil
        )
        let adj = youtubeOnly.consensusAdjustment(genreBaseline: base)
        XCTAssertLessThan(abs(adj), 0.01,
                          "An average movie with X unavailable must read neutral, not bearish")
    }

    /// A measured zero is a real bearish fact and must still register.
    func testMeasuredZeroIsNotTheSameAsMissing() {
        let measured = SocialSignal(youtubeTrailerViews7d: Int(base.trailerViewsMean),
                                    youtubeEngagementRate: base.engagementMean,
                                    xMentions24h: 0, xSentiment: 0)
        let missing = SocialSignal(youtubeTrailerViews7d: Int(base.trailerViewsMean),
                                   youtubeEngagementRate: base.engagementMean,
                                   xMentions24h: nil, xSentiment: nil)
        XCTAssertLessThan(measured.consensusAdjustment(genreBaseline: base),
                          missing.consensusAdjustment(genreBaseline: base))
    }

    func testPartialSignalStillRanksCorrectly() {
        let hot = SocialSignal(youtubeTrailerViews7d: 40_000_000,
                               youtubeEngagementRate: 0.05)
        let cold = SocialSignal(youtubeTrailerViews7d: 200_000,
                                youtubeEngagementRate: 0.004)
        XCTAssertGreaterThan(hot.consensusAdjustment(genreBaseline: base), 0.1)
        XCTAssertLessThan(cold.consensusAdjustment(genreBaseline: base), -0.1)
    }

    func testEmptySignalIsNeutralAndReportsNoData() {
        let empty = SocialSignal()
        XCTAssertEqual(empty.consensusAdjustment(genreBaseline: base), 0)
        XCTAssertFalse(empty.hasAnyData)
        XCTAssertEqual(empty.coverage, 0)
    }

    // MARK: - Coverage

    func testCoverageReflectsWhichSourcesReported() {
        XCTAssertEqual(SocialSignal().coverage, 0, accuracy: 0.001)
        XCTAssertEqual(
            SocialSignal(youtubeTrailerViews7d: 1, youtubeEngagementRate: 0.02).coverage,
            0.70, accuracy: 0.001)
        XCTAssertEqual(
            SocialSignal(xMentions24h: 1, xSentiment: 0.5).coverage,
            0.50, accuracy: 0.001)
        XCTAssertEqual(
            SocialSignal(youtubeTrailerViews7d: 1, youtubeEngagementRate: 0.02,
                         xMentions24h: 1, xSentiment: 0.5).coverage,
            1.0, accuracy: 0.001)
    }

    // MARK: - Engagement rate

    /// The old like-ratio formula, likes / (likes + likes/10), returned
    /// 0.909 for every input above 9 — it carried no information at all.
    /// Engagement rate has to actually discriminate.
    func testEngagementRateDiscriminates() {
        let loved = SocialSignal(youtubeTrailerViews7d: Int(base.trailerViewsMean),
                                 youtubeEngagementRate: 0.05)
        let ignored = SocialSignal(youtubeTrailerViews7d: Int(base.trailerViewsMean),
                                   youtubeEngagementRate: 0.002)
        XCTAssertGreaterThan(loved.consensusAdjustment(genreBaseline: base),
                             ignored.consensusAdjustment(genreBaseline: base))
    }

    // MARK: - Composite merge

    func testUnionFillsGapsWithoutOverwriting() {
        let yt = SocialSignal(youtubeTrailerViews7d: 5_000_000,
                              youtubeEngagementRate: 0.03)
        let x  = SocialSignal(xMentions24h: 40_000, xSentiment: 0.5)
        let merged = CompositeSignalSource.union(yt, x)
        XCTAssertEqual(merged.youtubeTrailerViews7d, 5_000_000)
        XCTAssertEqual(merged.youtubeEngagementRate ?? 0, 0.03, accuracy: 1e-9)
        XCTAssertEqual(merged.xMentions24h, 40_000)
        XCTAssertEqual(merged.xSentiment ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(merged.coverage, 1.0, accuracy: 0.001)
    }

    func testUnionPreservesAMeasuredNeutralSentiment() {
        // 0.0 is a real reading. The old merge treated it as "empty" and
        // let a later source clobber it.
        let first = SocialSignal(xMentions24h: 1_000, xSentiment: 0.0)
        let second = SocialSignal(xMentions24h: 9_999, xSentiment: 0.9)
        let merged = CompositeSignalSource.union(first, second)
        XCTAssertEqual(merged.xSentiment ?? -1, 0.0, accuracy: 1e-9)
        XCTAssertEqual(merged.xMentions24h, 1_000)
    }

    func testUnionWithNoPriorReturnsTheIncomingSignal() {
        let x = SocialSignal(xMentions24h: 7, xSentiment: -0.2)
        XCTAssertEqual(CompositeSignalSource.union(nil, x), x)
    }
}

// MARK: - Trailer view curve

final class TrailerViewCurveTests: XCTestCase {

    /// A trailer no older than the window has done all of its viewing
    /// inside it.
    func testFreshVideoCountsEntirely() {
        XCTAssertEqual(TrailerViewCurve.trailingWeekFraction(ageDays: 1), 1.0, accuracy: 1e-9)
        XCTAssertEqual(TrailerViewCurve.trailingWeekFraction(ageDays: 7), 1.0, accuracy: 1e-9)
    }

    /// The defect this guards: the field is named `...Views7d` but was
    /// being handed a lifetime count, so a six-month-old trailer with 50M
    /// cumulative views read exactly as bullish as one that did 50M in
    /// its first week.
    func testOlderVideosContributeLess() {
        let week = TrailerViewCurve.trailingWeekFraction(ageDays: 7)
        let month = TrailerViewCurve.trailingWeekFraction(ageDays: 30)
        let halfYear = TrailerViewCurve.trailingWeekFraction(ageDays: 180)
        XCTAssertGreaterThan(week, month)
        XCTAssertGreaterThan(month, halfYear)
        XCTAssertLessThan(halfYear, 0.01)
    }

    func testFractionIsMonotonicAndBounded() {
        var previous = 1.1
        for age in stride(from: 1.0, through: 365.0, by: 3.0) {
            let f = TrailerViewCurve.trailingWeekFraction(ageDays: age)
            XCTAssertTrue((0...1).contains(f), "fraction out of range at age \(age)")
            XCTAssertLessThanOrEqual(f, previous + 1e-9, "not monotonic at age \(age)")
            previous = f
        }
    }

    func testTrailingWeekViewsSeparatesFreshFromStale() {
        let now = Date()
        let fresh = TrailerViewCurve.trailingWeekViews(
            lifetime: 50_000_000,
            publishedAt: now.addingTimeInterval(-5 * 86_400), now: now)
        let stale = TrailerViewCurve.trailingWeekViews(
            lifetime: 50_000_000,
            publishedAt: now.addingTimeInterval(-180 * 86_400), now: now)
        XCTAssertEqual(fresh, 50_000_000)
        XCTAssertLessThan(stale, 1_000_000)
    }

    /// No publish date is a real case; it must not silently become a
    /// lifetime count masquerading as a weekly one.
    func testMissingPublishDateFallsBackToAMedianAge() {
        let views = TrailerViewCurve.trailingWeekViews(lifetime: 10_000_000, publishedAt: nil)
        XCTAssertLessThan(views, 10_000_000)
        XCTAssertGreaterThan(views, 0)
    }

    func testHandlesZeroAndNegativeAges() {
        XCTAssertEqual(TrailerViewCurve.trailingWeekFraction(ageDays: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(TrailerViewCurve.trailingWeekFraction(ageDays: -5), 1.0, accuracy: 1e-9)
    }
}

// MARK: - Trailer matching

final class TrailerMatcherTests: XCTestCase {

    func testAcceptsAnOfficialTrailer() {
        XCTAssertTrue(TrailerMatcher.isPlausibleTrailer(
            videoTitle: "Dune: Part Three | Official Trailer",
            channelTitle: "Warner Bros. Pictures",
            movieTitle: "Dune: Part Three"))
    }

    func testAcceptsATeaser() {
        XCTAssertTrue(TrailerMatcher.isPlausibleTrailer(
            videoTitle: "AVATAR 4 - Teaser Trailer",
            channelTitle: "20th Century Studios",
            movieTitle: "Avatar 4"))
    }

    /// The defect this guards: taking the top search hit on faith meant a
    /// reaction video's engagement could end up pricing the chain.
    func testRejectsReactionsAndBreakdowns() {
        XCTAssertFalse(TrailerMatcher.isPlausibleTrailer(
            videoTitle: "Dune Part Three Trailer REACTION!!",
            channelTitle: "Some Fan Channel",
            movieTitle: "Dune: Part Three"))
        XCTAssertFalse(TrailerMatcher.isPlausibleTrailer(
            videoTitle: "Dune Part Three Trailer Breakdown - Every Detail",
            channelTitle: "Movie Explainers",
            movieTitle: "Dune: Part Three"))
    }

    func testRejectsAConcept() {
        XCTAssertFalse(TrailerMatcher.isPlausibleTrailer(
            videoTitle: "Superman Legacy - Concept Trailer (Fan Made)",
            channelTitle: "Fan Edits",
            movieTitle: "Superman Legacy"))
    }

    func testRejectsAnUnrelatedMovie() {
        XCTAssertFalse(TrailerMatcher.isPlausibleTrailer(
            videoTitle: "Wicked: For Good | Official Trailer",
            channelTitle: "Universal Pictures",
            movieTitle: "Dune: Part Three"))
    }

    func testRejectsNonTrailerContent() {
        XCTAssertFalse(TrailerMatcher.isPlausibleTrailer(
            videoTitle: "Dune: Part Three — Behind The Scenes",
            channelTitle: "Warner Bros. Pictures",
            movieTitle: "Dune: Part Three"))
    }

    /// Titles differing only by stop words and punctuation should match.
    func testToleratesPunctuationAndStopWords() {
        XCTAssertTrue(TrailerMatcher.isPlausibleTrailer(
            videoTitle: "THE LEGEND OF ZELDA — Official Trailer (2027)",
            channelTitle: "Sony Pictures",
            movieTitle: "The Legend of Zelda"))
    }
}

// MARK: - Diagnostics

final class SocialSourceDiagnosticsTests: XCTestCase {

    func testUnconfiguredReadsAsNotConfigured() {
        let d = SocialSourceDiagnostics(name: "YouTube", configured: false)
        XCTAssertFalse(d.isHealthy)
        XCTAssertEqual(d.statusLine, "Not configured.")
    }

    /// The defect this guards: the Data Sources screen reported a source
    /// as LIVE whenever an API key string was non-empty, so a quota-
    /// exhausted or misconfigured key looked healthy.
    func testQuotaExhaustionIsNotHealthy() {
        let d = SocialSourceDiagnostics(name: "YouTube", configured: true,
                                        lastSuccessAt: Date(), quotaExhausted: true)
        XCTAssertFalse(d.isHealthy)
        XCTAssertTrue(d.statusLine.contains("quota"))
    }

    func testErrorIsNotHealthy() {
        let d = SocialSourceDiagnostics(name: "YouTube", configured: true,
                                        lastAttemptAt: Date(),
                                        lastError: "HTTP 500.")
        XCTAssertFalse(d.isHealthy)
        XCTAssertTrue(d.statusLine.contains("HTTP 500"))
    }

    func testSuccessfulPullIsHealthy() {
        let d = SocialSourceDiagnostics(name: "YouTube", configured: true,
                                        lastAttemptAt: Date(),
                                        lastSuccessAt: Date(),
                                        moviesCovered: 12)
        XCTAssertTrue(d.isHealthy)
        XCTAssertTrue(d.statusLine.contains("12"))
    }
}
