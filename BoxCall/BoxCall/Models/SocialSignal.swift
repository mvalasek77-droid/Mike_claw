import Foundation

/// Raw crowd-attention signal for a movie, aggregated from social
/// platforms. Feeds into TrackingDataSource to adjust the consensus
/// opening estimate — trailer engagement and mention velocity are
/// legit leading indicators for opening weekend.
///
/// Every measurement is optional, and that is load-bearing. A source
/// that could not be reached reports `nil`, which is a different claim
/// from "I looked and the number was zero". Folding an unreachable
/// source in as zero drags the whole model toward whatever the baseline
/// treats as pessimistic — with the X endpoint stubbed, that alone put a
/// permanent bearish tilt on every movie in the catalog.
struct SocialSignal: Hashable, Codable {
    /// Views the trailer picked up in the trailing 7 days. `nil` when no
    /// YouTube data was retrieved.
    var youtubeTrailerViews7d: Int?
    /// Likes per view on the trailer, typically 0.01–0.04 for a trailer
    /// that is landing well.
    ///
    /// YouTube removed public dislike counts in December 2021, so a true
    /// like/(like+dislike) ratio is no longer obtainable from the API.
    /// Engagement rate is the honest proxy: people who like a trailer
    /// enough to tap the button are the same population a like ratio was
    /// trying to measure.
    var youtubeEngagementRate: Double?
    /// Number of X (Twitter) mentions in the last 24h. `nil` when the X
    /// signal was unavailable.
    var xMentions24h: Int?
    /// Rough sentiment score −1 (uniformly negative) → +1 (uniformly
    /// positive). `nil` when unavailable — distinct from 0.0, which is a
    /// measured neutral.
    var xSentiment: Double?
    /// When these numbers were captured.
    var capturedAt: Date

    init(youtubeTrailerViews7d: Int? = nil,
         youtubeEngagementRate: Double? = nil,
         xMentions24h: Int? = nil,
         xSentiment: Double? = nil,
         capturedAt: Date = Date()) {
        self.youtubeTrailerViews7d = youtubeTrailerViews7d
        self.youtubeEngagementRate = youtubeEngagementRate
        self.xMentions24h = xMentions24h
        self.xSentiment = xSentiment
        self.capturedAt = capturedAt
    }

    // MARK: - Component weights

    /// Relative weight of each measurement in the blended adjustment.
    /// These sum to 1.0 when every source reported.
    private enum Weight {
        static let views: Double = 0.50
        static let mentions: Double = 0.30
        static let mood: Double = 0.20
        /// Within the mood term, how much comes from each source.
        static let moodFromX: Double = 0.70
        static let moodFromEngagement: Double = 0.30
    }

    /// Fraction of the model that actually had data behind it, 0…1.
    ///
    /// A reading built from YouTube alone covers 0.7 of the model; the
    /// desk uses this to decide how much to trust the number rather than
    /// treating a partial read as a confident one.
    var coverage: Double {
        var covered = 0.0
        if youtubeTrailerViews7d != nil { covered += Weight.views }
        if xMentions24h != nil { covered += Weight.mentions }
        if xSentiment != nil || youtubeEngagementRate != nil { covered += Weight.mood }
        return covered
    }

    /// True when at least one source reported something usable.
    var hasAnyData: Bool { coverage > 0 }

    /// A single scalar in [-0.30, +0.30] used to shift the consensus
    /// opening. Positive = crowd is bullish → consensus up.
    ///
    /// Each present component contributes its z-score (capped at ±2σ)
    /// scaled by its weight. The total is then divided by the coverage
    /// actually achieved, so the sources that *did* report speak for the
    /// whole model instead of being diluted toward zero — or, worse,
    /// biased by a missing source's default.
    func consensusAdjustment(genreBaseline: SignalBaseline) -> Double {
        var weighted = 0.0

        if let views = youtubeTrailerViews7d {
            let z = cappedZ(Double(views),
                            mean: genreBaseline.trailerViewsMean,
                            sigma: genreBaseline.trailerViewsSigma)
            weighted += Weight.views * (z / 2)
        }

        if let mentions = xMentions24h {
            let z = cappedZ(Double(mentions),
                            mean: genreBaseline.mentionsMean,
                            sigma: genreBaseline.mentionsSigma)
            weighted += Weight.mentions * (z / 2)
        }

        // Mood blends explicit X sentiment with trailer engagement.
        // Whichever of the two is available carries the term.
        var moodTotal = 0.0
        var moodWeight = 0.0
        if let sentiment = xSentiment {
            moodTotal += max(-1, min(1, sentiment)) * Weight.moodFromX
            moodWeight += Weight.moodFromX
        }
        if let engagement = youtubeEngagementRate {
            let z = cappedZ(engagement,
                            mean: genreBaseline.engagementMean,
                            sigma: genreBaseline.engagementSigma)
            moodTotal += (z / 2) * Weight.moodFromEngagement
            moodWeight += Weight.moodFromEngagement
        }
        if moodWeight > 0 {
            weighted += Weight.mood * (moodTotal / moodWeight)
        }

        let covered = coverage
        guard covered > 0 else { return 0 }
        let normalized = weighted / covered
        return max(-0.30, min(0.30, normalized))
    }

    /// z-score capped at ±2σ so one runaway number cannot dominate.
    private func cappedZ(_ x: Double, mean: Double, sigma: Double) -> Double {
        guard sigma > 0, x.isFinite else { return 0 }
        return max(-2, min(2, (x - mean) / sigma))
    }
}

/// Genre-cohort baseline for z-scoring. In production this comes
/// from a server-side model calibrated against historical opens.
struct SignalBaseline: Hashable {
    let trailerViewsMean: Double
    let trailerViewsSigma: Double
    let mentionsMean: Double
    let mentionsSigma: Double
    /// Likes-per-view on a trailer. Wide-release trailers cluster around
    /// 2%, with well-received ones pushing past 3%.
    let engagementMean: Double
    let engagementSigma: Double

    /// Rough one-size-fits-all defaults — replace with per-genre models.
    static let generic = SignalBaseline(
        trailerViewsMean:  6_000_000,
        trailerViewsSigma: 8_000_000,
        mentionsMean:      12_000,
        mentionsSigma:     18_000,
        engagementMean:    0.020,
        engagementSigma:   0.012
    )
}
