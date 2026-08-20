import Foundation

/// Raw crowd-attention signal for a movie, aggregated from social
/// platforms. Feeds into TrackingDataSource to adjust the consensus
/// opening estimate — trailer engagement and mention velocity are
/// legit leading indicators for opening weekend.
struct SocialSignal: Hashable, Codable {
    /// Total YouTube views on official trailer(s) in the last 7 days.
    var youtubeTrailerViews7d: Int
    /// YouTube likes / (likes + dislikes) if available, else nil.
    var youtubeLikeRatio: Double?
    /// Number of X (Twitter) mentions in the last 24h.
    var xMentions24h: Int
    /// Rough sentiment score −1 (uniformly negative) → +1 (uniformly positive).
    var xSentiment: Double
    /// When these numbers were captured.
    var capturedAt: Date

    /// A single scalar in roughly [-0.3, +0.3] used to shift the
    /// consensus opening. Positive = crowd is bullish → consensus up.
    ///
    /// Weights (tunable):
    ///   50% trailer views z-score, capped at ±2σ
    ///   30% mention velocity z-score, capped at ±2σ
    ///   20% blended sentiment (X sentiment × YT like ratio)
    func consensusAdjustment(genreBaseline: SignalBaseline) -> Double {
        let viewsZ = zScore(Double(youtubeTrailerViews7d),
                            mean: genreBaseline.trailerViewsMean,
                            sigma: genreBaseline.trailerViewsSigma)
        let mentionsZ = zScore(Double(xMentions24h),
                               mean: genreBaseline.mentionsMean,
                               sigma: genreBaseline.mentionsSigma)
        let clampedViews = max(-2, min(2, viewsZ))
        let clampedMentions = max(-2, min(2, mentionsZ))

        let likeRatioScore = ((youtubeLikeRatio ?? 0.8) - 0.7) / 0.3  // [-2.3, 1.0]
        let sentimentBlend = (xSentiment * 0.7) + (max(-1, min(1, likeRatioScore)) * 0.3)

        let raw = 0.50 * (clampedViews / 2)      // → [-0.25, +0.25]
               + 0.30 * (clampedMentions / 2)    // → [-0.15, +0.15]
               + 0.20 * sentimentBlend           // → [-0.20, +0.20]

        return max(-0.30, min(0.30, raw))
    }

    private func zScore(_ x: Double, mean: Double, sigma: Double) -> Double {
        guard sigma > 0 else { return 0 }
        return (x - mean) / sigma
    }
}

/// Genre-cohort baseline for z-scoring. In production this comes
/// from a server-side model calibrated against historical opens.
struct SignalBaseline: Hashable {
    let trailerViewsMean: Double
    let trailerViewsSigma: Double
    let mentionsMean: Double
    let mentionsSigma: Double

    /// Rough one-size-fits-all defaults — replace with per-genre models.
    static let generic = SignalBaseline(
        trailerViewsMean:  6_000_000,
        trailerViewsSigma: 8_000_000,
        mentionsMean:      12_000,
        mentionsSigma:     18_000
    )
}
