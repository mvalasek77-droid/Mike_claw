import Foundation
import Combine

// MARK: - Pure model

/// The math behind the pulse, kept free of state and of the main actor
/// so tests can drive it directly with fixed inputs.
enum SentimentModel {
    /// How long it takes an unattended pulse to fall halfway back to
    /// neutral.
    static let defaultHalfLife: TimeInterval = 90

    /// Scales raw score-change-per-second into the [-1, 1] velocity band.
    /// Tuned so a 0.05 move in one second reads as a strong shock.
    static let velocityScale: Double = 12

    /// Turns a slow `SocialSignal` capture into a baseline crowd score.
    ///
    /// `SocialSignal.consensusAdjustment` already produces a calibrated
    /// number in roughly [-0.3, +0.3] for shifting the consensus opening.
    /// The pulse wants the same opinion expressed on a full [-1, 1]
    /// scale, so this just rescales it.
    static func baseline(from signal: SocialSignal,
                         genreBaseline: SignalBaseline = .generic) -> Double {
        SentimentPulse.clampSigned(signal.consensusAdjustment(genreBaseline: genreBaseline) / 0.30)
    }

    /// Net directional read from order flow. Call buying is bullish on
    /// the movie, put buying is bearish.
    static func flowScore(callVolume: Double, putVolume: Double) -> Double {
        let total = callVolume + putVolume
        guard total > 0 else { return 0 }
        // Damped so a single large trade cannot pin the pulse.
        return SentimentPulse.clampSigned(((callVolume - putVolume) / total) * 0.7)
    }

    /// Collapse a window of individual chatter impacts into the three
    /// numbers the agents care about.
    ///
    /// - mean: which way the crowd leans.
    /// - dispersion: how much they disagree, from the spread of impacts.
    /// - volume: how loud it is, from how many items landed.
    static func aggregate(impacts: [Double], loudAt: Int = 10)
        -> (mean: Double, dispersion: Double, volume: Double) {
        guard !impacts.isEmpty else { return (0, 0.3, 0) }
        let n = Double(impacts.count)
        let mean = impacts.reduce(0, +) / n
        let variance = impacts.reduce(0) { $0 + pow($1 - mean, 2) } / n
        let stddev = sqrt(variance)
        return (
            mean: SentimentPulse.clampSigned(mean),
            // A stddev of ~0.6 across items is already a badly split room.
            dispersion: SentimentPulse.clampUnit(stddev / 0.6),
            volume: SentimentPulse.clampUnit(n / Double(max(1, loudAt)))
        )
    }

    /// Advance a pulse toward a new target reading.
    ///
    /// Score moves fractionally, at a rate set by `halfLife`, so the
    /// pulse never teleports. Velocity is the *observed* rate of that
    /// move, smoothed, which is what the scalper and vol desk defend
    /// against.
    static func blend(previous: SentimentPulse,
                      targetScore: Double,
                      targetVolume: Double,
                      targetDispersion: Double,
                      elapsed: TimeInterval,
                      halfLife: TimeInterval = defaultHalfLife,
                      now: Date = Date()) -> SentimentPulse {
        let dt = max(0.001, elapsed)
        let alpha = 1 - pow(0.5, dt / max(0.001, halfLife))

        let newScore = SentimentPulse.clampSigned(
            previous.score + (SentimentPulse.clampSigned(targetScore) - previous.score) * alpha
        )

        // Rate of change per second, squashed into [-1, 1].
        let rate = (newScore - previous.score) / dt
        let instantaneous = tanh(rate * velocityScale)
        // Smooth so one tick of noise does not read as a narrative flip.
        let velocity = SentimentPulse.clampSigned(instantaneous * 0.6 + previous.velocity * 0.4)

        // Volume and dispersion track their targets on the same clock.
        let volume = previous.volume + (SentimentPulse.clampUnit(targetVolume) - previous.volume) * alpha
        let dispersion = previous.dispersion
            + (SentimentPulse.clampUnit(targetDispersion) - previous.dispersion) * alpha

        return SentimentPulse(score: newScore, velocity: velocity,
                              volume: volume, dispersion: dispersion,
                              capturedAt: now)
    }

    /// Let a pulse relax toward neutral when nothing new arrives.
    static func decayed(_ pulse: SentimentPulse,
                        elapsed: TimeInterval,
                        halfLife: TimeInterval = defaultHalfLife,
                        now: Date = Date()) -> SentimentPulse {
        blend(previous: pulse, targetScore: 0,
              targetVolume: 0, targetDispersion: 0.3,
              elapsed: elapsed, halfLife: halfLife, now: now)
    }
}

// MARK: - Live engine

/// Maintains a live `SentimentPulse` per movie and the stream of chatter
/// that produced it.
///
/// Inputs, in order of how much they are trusted:
///   1. `SocialSignal` captures from the real YouTube / X sources — the
///      slow baseline the pulse reverts toward.
///   2. Real order flow from the app's own users.
///   3. Hot Takes posted in the feed.
///   4. Market headlines from the event generator.
///   5. Ambient synthetic chatter, so the desk still breathes when no
///      API keys are configured.
@MainActor
final class SentimentEngine: ObservableObject {
    static let shared = SentimentEngine()

    /// Current read per movie id.
    @Published private(set) var pulses: [String: SentimentPulse] = [:]
    /// Rolling score samples per movie id, for the desk sparkline.
    @Published private(set) var history: [String: [SentimentSample]] = [:]
    /// Newest chatter first, across all movies.
    @Published private(set) var events: [SentimentEvent] = []

    /// One timestamped nudge inside the rolling attention window.
    private struct Impact {
        let at: Date
        let value: Double
    }

    /// Slow baseline from the real social sources, per movie id.
    private var baselines: [String: Double] = [:]
    /// How much of the social model actually had data behind each
    /// baseline, 0…1. A YouTube-only read covers 0.7 and is trusted
    /// proportionally less than a full YouTube + X read.
    private var baselineCoverage: [String: Double] = [:]
    /// Last time a capture produced a visible chatter item, per movie.
    private var lastIngestAt: [String: Date] = [:]
    /// Timestamped impacts inside the rolling attention window.
    private var impactWindow: [String: [Impact]] = [:]
    private var lastTickAt: Date = Date()

    /// How far back the attention window reaches.
    private let windowSeconds: TimeInterval = 45
    private let historyCap = 90
    private let eventCap = 60
    /// Chance per movie per tick that ambient chatter lands.
    private let chatterChance: Double = 0.18

    private init() {}

    // MARK: - Read

    func pulse(for movieId: String) -> SentimentPulse {
        pulses[movieId] ?? .flat
    }

    func scoreHistory(for movieId: String) -> [SentimentSample] {
        history[movieId] ?? []
    }

    func chatter(for movieId: String) -> [SentimentEvent] {
        events.filter { $0.movieId == movieId }
    }

    /// Movies sorted by how far sentiment has run, hottest first. Powers
    /// the "what the desk is watching" strip.
    func moversByHeat(limit: Int = 5) -> [(movieId: String, pulse: SentimentPulse)] {
        let ranked = pulses
            .map { (movieId: $0.key, pulse: $0.value) }
            .sorted { abs($0.pulse.score) > abs($1.pulse.score) }
        return Array(ranked.prefix(limit))
    }

    // MARK: - Ingest

    /// Fold a real social capture into the slow baseline.
    ///
    /// A capture with no measurements behind it is discarded rather than
    /// stored as a neutral opinion — the desk should keep quoting off
    /// whatever it already knew, not be told the crowd went quiet.
    func ingest(signal: SocialSignal, for movieId: String,
                genreBaseline: SignalBaseline = .generic,
                now: Date = Date()) {
        guard signal.hasAnyData else { return }
        let score = SentimentModel.baseline(from: signal, genreBaseline: genreBaseline)
        baselines[movieId] = score
        baselineCoverage[movieId] = signal.coverage

        // Refreshes can arrive in bursts when someone pulls to refresh
        // repeatedly. Update the baseline every time, but only publish a
        // visible chatter item once a minute so the window is not stuffed
        // with duplicates of the same capture.
        if let last = lastIngestAt[movieId], now.timeIntervalSince(last) < 60 { return }
        lastIngestAt[movieId] = now

        let text: String
        if let views = signal.youtubeTrailerViews7d {
            let engagement = signal.youtubeEngagementRate
                .map { String(format: " at %.1f%% engagement", $0 * 100) } ?? ""
            text = "Trailer pulling \(compact(views)) views this week\(engagement)."
        } else if let mentions = signal.socialMentions24h {
            text = "\(compact(mentions)) mentions in the last 24h."
        } else {
            text = "Social capture refreshed, crowd reads \(signed(score))."
        }
        record(movieId: movieId, source: .trailer, impact: score, text: text, at: now)
    }

    /// Drop state for movies that are no longer listed.
    ///
    /// Every per-movie dictionary here is keyed by an id that can vanish
    /// when the catalog prunes an opened film. Without this the maps grow
    /// for the life of the process.
    func prune(keeping liveIds: Set<String>) {
        pulses = pulses.filter { liveIds.contains($0.key) }
        history = history.filter { liveIds.contains($0.key) }
        baselines = baselines.filter { liveIds.contains($0.key) }
        baselineCoverage = baselineCoverage.filter { liveIds.contains($0.key) }
        impactWindow = impactWindow.filter { liveIds.contains($0.key) }
        lastIngestAt = lastIngestAt.filter { liveIds.contains($0.key) }
        events.removeAll { !liveIds.contains($0.movieId) }
    }

    /// A real trade moved the tape. Call buying reads bullish.
    func recordFlow(movieId: String, side: ContractSide, quantity: Int) {
        let magnitude = min(0.8, 0.12 + Double(quantity) * 0.02)
        let impact = side == .call ? magnitude : -magnitude
        record(movieId: movieId, source: .flow, impact: impact,
               text: "\(quantity) \(side.display) bought — \(side == .call ? "bullish" : "bearish") flow.")
    }

    /// Someone posted a Hot Take in the feed.
    func recordHotTake(movieId: String, side: ContractSide, handle: String) {
        let impact = side == .call ? 0.35 : -0.35
        record(movieId: movieId, source: .chatter, impact: impact,
               text: "@\(handle) went \(side.display) and said so publicly.")
    }

    /// A published review landed.
    func recordReview(movieId: String, rating: Int, handle: String) {
        // Ratings run 1...5; map to [-0.6, +0.6].
        let impact = (Double(rating) - 3) / 2 * 0.6
        record(movieId: movieId, source: .review, impact: impact,
               text: "@\(handle) filed a \(rating)-star review.")
    }

    /// A market headline fired. Magnitude arrives already signed.
    func recordHeadline(movieId: String, headline: String, magnitude: Double) {
        record(movieId: movieId, source: .headline,
               impact: SentimentPulse.clampSigned(magnitude * 3),
               text: headline)
    }

    // MARK: - Tick

    /// Advance every tracked movie's pulse. Called by `MarketService` on
    /// its own cadence so sentiment and prices move on the same clock.
    ///
    /// - Parameters:
    ///   - movieIds: everything currently listed.
    ///   - titles: used to write ambient chatter that names the film.
    ///   - now: injectable for tests.
    ///   - rng: injectable so ambient chatter is reproducible.
    func tick(movieIds: [String],
              titles: [String: String] = [:],
              now: Date = Date(),
              rng: inout SeededGenerator) {
        let elapsed = max(0.5, now.timeIntervalSince(lastTickAt))
        lastTickAt = now

        for id in movieIds {
            maybeGenerateChatter(movieId: id, title: titles[id], now: now, rng: &rng)

            // Trim the attention window, then read it.
            let window = (impactWindow[id] ?? []).filter {
                now.timeIntervalSince($0.at) <= windowSeconds
            }
            impactWindow[id] = window

            let agg = SentimentModel.aggregate(impacts: window.map(\.value))
            let baseline = baselines[id] ?? 0
            let coverage = baselineCoverage[id] ?? 0

            // The window is the news; the baseline is the standing view.
            // Weight the window more when it is loud, so a quiet movie
            // sits on its baseline instead of drifting on two comments.
            //
            // The baseline's share is scaled by how much of the social
            // model was actually observed. A movie we have no social read
            // on contributes nothing rather than dragging the pulse
            // toward a zero it never measured.
            let windowWeight = 0.35 + 0.45 * agg.volume
            let baselineWeight = (1 - windowWeight) * coverage
            let totalWeight = windowWeight + baselineWeight
            let target = totalWeight > 0
                ? SentimentPulse.clampSigned(
                    (agg.mean * windowWeight + baseline * baselineWeight) / totalWeight)
                : 0

            let previous = pulses[id] ?? .flat
            let next = SentimentModel.blend(
                previous: previous,
                targetScore: target,
                targetVolume: agg.volume,
                targetDispersion: agg.dispersion,
                elapsed: elapsed,
                now: now
            )
            pulses[id] = next
            appendSample(movieId: id, score: next.score, at: now)
        }
    }

    /// Convenience for production callers that do not hold a generator.
    func tick(movieIds: [String], titles: [String: String] = [:], now: Date = Date()) {
        var rng = SeededGenerator.live()
        tick(movieIds: movieIds, titles: titles, now: now, rng: &rng)
    }

    // MARK: - Internals

    private func record(movieId: String, source: SentimentEvent.Source,
                        impact: Double, text: String, at: Date = Date()) {
        let clamped = SentimentPulse.clampSigned(impact)
        impactWindow[movieId, default: []].append(Impact(at: at, value: clamped))
        events.insert(SentimentEvent(id: UUID(), movieId: movieId,
                                     source: source, text: text,
                                     impact: clamped, at: at), at: 0)
        if events.count > eventCap { events.removeLast(events.count - eventCap) }
    }

    /// Ambient crowd noise. Without this the desk sits perfectly still
    /// whenever no API keys are configured, which reads as broken rather
    /// than quiet. Impacts are drawn around the movie's own baseline so
    /// the chatter agrees with the standing view most of the time and
    /// occasionally does not — which is exactly what creates dispersion.
    private func maybeGenerateChatter(movieId: String, title: String?,
                                      now: Date, rng: inout SeededGenerator) {
        guard rng.unit() < chatterChance else { return }
        let baseline = baselines[movieId] ?? 0
        // Most chatter agrees with the baseline; one in five dissents.
        let dissent = rng.unit() < 0.20
        let magnitude = rng.double(in: 0.15...0.75)
        let direction: Double = dissent ? (baseline >= 0 ? -1 : 1) : (baseline >= 0 ? 1 : -1)
        let impact = SentimentPulse.clampSigned(direction * magnitude)

        let name = title ?? "it"
        let line = impact >= 0
            ? Self.bullishChatter.randomElement(using: &rng)?.replacingOccurrences(of: "{}", with: name)
            : Self.bearishChatter.randomElement(using: &rng)?.replacingOccurrences(of: "{}", with: name)

        record(movieId: movieId, source: .chatter, impact: impact,
               text: line ?? "Chatter on \(name).", at: now)
    }

    private func appendSample(movieId: String, score: Double, at: Date) {
        var pts = history[movieId] ?? []
        pts.append(SentimentSample(time: at, score: score))
        if pts.count > historyCap { pts.removeFirst(pts.count - historyCap) }
        history[movieId] = pts
    }

    private func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.0fK", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }

    private func signed(_ x: Double) -> String { String(format: "%+.2f", x) }

    // MARK: - Chatter corpus

    private static let bullishChatter: [String] = [
        "Early screening reactions for {} are glowing.",
        "{} trailer is trending again — third day running.",
        "Presales for {} just outpaced the studio's own forecast.",
        "Every critic who has seen {} is posting the same rave.",
        "{} is the only thing on the timeline this morning.",
        "Word of mouth on {} is spreading past the fan base.",
        "Theater chains added showtimes for {}."
    ]

    private static let bearishChatter: [String] = [
        "The {} marketing push has gone quiet this week.",
        "Embargo chatter on {} is not encouraging.",
        "{} lost a prime-weekend slot in two major markets.",
        "Trailer comments on {} have turned.",
        "Tracking for {} was revised down overnight.",
        "{} is getting buried by the competing release.",
        "Presales for {} stalled after the first day."
    ]
}
