import XCTest
@testable import BoxCall

final class SocialSignalTests: XCTestCase {
    func testAdjustment_clampedTo30Percent() {
        // Absurdly bullish signal — should still cap at +0.30
        let sig = SocialSignal(
            youtubeTrailerViews7d: 500_000_000,
            youtubeLikeRatio: 0.99,
            xMentions24h: 5_000_000,
            xSentiment: 1.0,
            capturedAt: Date()
        )
        let adj = sig.consensusAdjustment(genreBaseline: .generic)
        XCTAssertLessThanOrEqual(adj, 0.30 + 1e-6)
        XCTAssertGreaterThan(adj, 0.0)
    }

    func testAdjustment_negativeForCratering() {
        let sig = SocialSignal(
            youtubeTrailerViews7d: 0,
            youtubeLikeRatio: 0.1,
            xMentions24h: 0,
            xSentiment: -1.0,
            capturedAt: Date()
        )
        let adj = sig.consensusAdjustment(genreBaseline: .generic)
        XCTAssertLessThan(adj, 0.0)
        XCTAssertGreaterThanOrEqual(adj, -0.30 - 1e-6)
    }

    func testAdjustment_neutralAtBaseline() {
        let sig = SocialSignal(
            youtubeTrailerViews7d: Int(SignalBaseline.generic.trailerViewsMean),
            youtubeLikeRatio: 0.7,
            xMentions24h: Int(SignalBaseline.generic.mentionsMean),
            xSentiment: 0.0,
            capturedAt: Date()
        )
        let adj = sig.consensusAdjustment(genreBaseline: .generic)
        // Near zero — within ±0.05 tolerance for like-ratio blend.
        XCTAssertLessThan(abs(adj), 0.05)
    }
}
