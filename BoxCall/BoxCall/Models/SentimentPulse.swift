import Foundation

/// A fast-moving read on what the crowd is saying about one movie
/// *right now*.
///
/// This is deliberately distinct from `SocialSignal`, which is a slow,
/// snapshot-style capture used to anchor the consensus opening number.
/// A pulse ticks every few seconds and is what the market-making agents
/// actually quote off. Signal sets the fair value; pulse sets the skew.
struct SentimentPulse: Hashable, Codable {
    /// Crowd direction in [-1, +1]. Positive = bullish on the movie.
    var score: Double
    /// Rate of change of `score`, normalized to [-1, +1]. A big number
    /// here means the narrative flipped in the last few minutes, which
    /// is exactly when market makers get run over — so they widen.
    var velocity: Double
    /// Normalized chatter volume in [0, 1]. High volume means agents
    /// are willing to show more size.
    var volume: Double
    /// Disagreement in [0, 1]. Zero = everyone says the same thing;
    /// one = the timeline is at war. Dispersion widens spreads.
    var dispersion: Double
    /// When this reading was taken.
    var capturedAt: Date

    init(score: Double = 0,
         velocity: Double = 0,
         volume: Double = 0.35,
         dispersion: Double = 0.30,
         capturedAt: Date = Date()) {
        self.score = SentimentPulse.clampSigned(score)
        self.velocity = SentimentPulse.clampSigned(velocity)
        self.volume = SentimentPulse.clampUnit(volume)
        self.dispersion = SentimentPulse.clampUnit(dispersion)
        self.capturedAt = capturedAt
    }

    /// A quiet, opinionless market. Used as the cold-start default.
    static let flat = SentimentPulse()

    // MARK: - Derived

    /// Sentiment as the given side experiences it. A bullish crowd is
    /// good for Calls and bad for Puts, so Puts see the sign flipped.
    /// Every agent quotes off this rather than raw `score`.
    func directional(for side: ContractSide) -> Double {
        side == .call ? score : -score
    }

    /// Velocity as the given side experiences it.
    func directionalVelocity(for side: ContractSide) -> Double {
        side == .call ? velocity : -velocity
    }

    /// True when the tape just gapped — the narrative is moving faster
    /// than the desk can reprice. Agents defend by widening.
    var isShock: Bool { abs(velocity) > 0.55 }

    /// True when the crowd is loud *and* united. This is when momentum
    /// agents lean hardest.
    var isConviction: Bool { volume > 0.55 && dispersion < 0.35 }

    /// Crowd mood bucket, used for labels and color.
    var mood: SentimentMood {
        switch score {
        case 0.55...:      return .euphoric
        case 0.18..<0.55:  return .bullish
        case -0.18..<0.18: return .mixed
        case -0.55..<(-0.18): return .bearish
        default:           return .panicked
        }
    }

    /// Confidence the desk has in this reading, in [0, 1]. Loud and
    /// united reads high; quiet and fractured reads low. Agents scale
    /// their size by this.
    var confidence: Double {
        SentimentPulse.clampUnit(volume * (1 - dispersion * 0.8))
    }

    // MARK: - Clamps

    static func clampSigned(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        return min(max(x, -1), 1)
    }

    static func clampUnit(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        return min(max(x, 0), 1)
    }
}

/// Crowd mood bucket. Drives the gauge label and color on the desk.
enum SentimentMood: String, Codable, CaseIterable {
    case euphoric, bullish, mixed, bearish, panicked

    var label: String {
        switch self {
        case .euphoric: return "Euphoric"
        case .bullish:  return "Bullish"
        case .mixed:    return "Mixed"
        case .bearish:  return "Bearish"
        case .panicked: return "Panicked"
        }
    }

    var glyph: String {
        switch self {
        case .euphoric: return "flame.fill"
        case .bullish:  return "arrow.up.right"
        case .mixed:    return "arrow.left.and.right"
        case .bearish:  return "arrow.down.right"
        case .panicked: return "exclamationmark.triangle.fill"
        }
    }

    /// Plain-English line for people who do not speak markets.
    var blurb: String {
        switch self {
        case .euphoric: return "The timeline is on fire for this one."
        case .bullish:  return "Crowd is leaning positive."
        case .mixed:    return "No clear read from the crowd."
        case .bearish:  return "Crowd is souring on it."
        case .panicked: return "The narrative is collapsing."
        }
    }
}

/// One piece of chatter that moved the pulse. The desk shows a live
/// stream of these so the sentiment number never feels like a black box.
struct SentimentEvent: Identifiable, Hashable {
    let id: UUID
    let movieId: String
    let source: Source
    let text: String
    /// How much this single item pushed the score, in [-1, +1].
    let impact: Double
    let at: Date

    enum Source: String, Codable, CaseIterable {
        case trailer, chatter, review, flow, headline

        var label: String {
            switch self {
            case .trailer:  return "Trailer"
            case .chatter:  return "Chatter"
            case .review:   return "Review"
            case .flow:     return "Order flow"
            case .headline: return "Headline"
            }
        }

        var glyph: String {
            switch self {
            case .trailer:  return "play.rectangle.fill"
            case .chatter:  return "bubble.left.and.bubble.right.fill"
            case .review:   return "star.bubble.fill"
            case .flow:     return "arrow.left.arrow.right"
            case .headline: return "newspaper.fill"
            }
        }
    }
}

/// One sampled pulse, kept for the sentiment sparkline on the desk.
struct SentimentSample: Hashable, Codable {
    let time: Date
    let score: Double
}
