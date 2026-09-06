import Foundation

// MARK: - Context handed to every agent

/// Everything an agent is allowed to see when it quotes. Deliberately a
/// value type with no service references: an agent is a pure function of
/// this struct plus its random stream, which is what makes the whole
/// desk testable.
struct QuoteContext {
    /// The line being quoted.
    let contract: Contract
    /// Theoretical value before any agent opinion is applied. This is
    /// the demand-driven mark the existing pricing model produces.
    let fairValue: Double
    /// Live crowd read for the underlying movie.
    let pulse: SentimentPulse
    /// Rolling support / resistance, when there is enough tape for it.
    let level: SRLevel?
    /// Days until the movie opens. Contracts get riskier to quote as
    /// expiry approaches, because there is less time to hedge out.
    let daysToRelease: Int
    /// The desk's net position in this contract. Positive = the desk is
    /// long and wants to sell; negative = short and wants to buy back.
    let inventory: Double

    init(contract: Contract,
         fairValue: Double,
         pulse: SentimentPulse,
         level: SRLevel? = nil,
         daysToRelease: Int = 30,
         inventory: Double = 0) {
        self.contract = contract
        self.fairValue = max(0.01, fairValue)
        self.pulse = pulse
        self.level = level
        self.daysToRelease = max(0, daysToRelease)
        self.inventory = inventory
    }

    var side: ContractSide { contract.side }

    /// Sentiment as *this* contract experiences it. Bullish crowd is
    /// tailwind for a Call and headwind for a Put.
    var directional: Double { pulse.directional(for: side) }

    /// Sentiment momentum as this contract experiences it.
    var directionalVelocity: Double { pulse.directionalVelocity(for: side) }

    /// 0 when expiry is far away, 1 on opening night. Everything widens
    /// as this climbs — there is less time to work out of a bad fill.
    var expiryPressure: Double {
        1 - min(1, Double(daysToRelease) / 30.0)
    }

    /// How badly the desk wants to shed risk, in [-1, +1]. Positive
    /// means "I am long, shade me down so I get hit on the offer."
    var inventoryPressure: Double {
        SentimentPulse.clampSigned(inventory / 250.0)
    }
}

// MARK: - What an agent publishes

/// Where an agent is leaning this tick. Drives the desk UI badge.
enum AgentStance: String, Codable, CaseIterable {
    /// Wants to buy — bid is aggressive, size is on the bid.
    case bidding
    /// Wants to sell — offer is aggressive, size is on the ask.
    case offering
    /// Quoting both sides evenly.
    case balanced
    /// Refuses to quote one or both sides. Risk is too high.
    case steppingAway

    var label: String {
        switch self {
        case .bidding:      return "Bidding"
        case .offering:     return "Offering"
        case .balanced:     return "Two-sided"
        case .steppingAway: return "Stepped away"
        }
    }

    var glyph: String {
        switch self {
        case .bidding:      return "arrow.up.circle.fill"
        case .offering:     return "arrow.down.circle.fill"
        case .balanced:     return "equal.circle.fill"
        case .steppingAway: return "hand.raised.fill"
        }
    }
}

/// Palette slot for an agent. Kept free of SwiftUI so the pricing layer
/// stays importable by tests and non-UI targets.
enum AgentTint: String, Codable, CaseIterable {
    case bull, bear, gold, violet, steel
}

/// One agent's published market for one contract.
struct AgentQuote: Identifiable, Hashable {
    let agentId: String
    let agentName: String
    let glyph: String
    let tint: AgentTint
    let quote: Quote
    let stance: AgentStance
    /// Plain-English reason, shown live on the desk so the number is
    /// never a black box.
    let rationale: String

    var id: String { agentId }

    var bid: Double { quote.bid }
    var ask: Double { quote.ask }
    var bidSize: Int { quote.bidSize }
    var askSize: Int { quote.askSize }

    /// An agent that shows no size on either side is not in the market.
    var isQuoting: Bool { quote.bidSize > 0 || quote.askSize > 0 }
}

// MARK: - The protocol

/// A background trader that publishes a two-sided market.
///
/// Agents never mutate shared state and never reach for a service. Give
/// one the same `QuoteContext` and the same seed and it returns the same
/// quote forever, which is the whole point.
protocol MarketMakingAgent {
    var id: String { get }
    var name: String { get }
    /// One line describing the strategy, shown on the desk roster.
    var blurb: String { get }
    var glyph: String { get }
    var tint: AgentTint { get }

    func quote(_ ctx: QuoteContext, rng: inout SeededGenerator) -> AgentQuote
}

// MARK: - Shared quote construction

extension MarketMakingAgent {
    /// Smallest market any agent is allowed to show, in Reel Coins.
    var minimumSpread: Double { 0.02 }
    /// Bounds on half-spread as a fraction of center price.
    var halfSpreadBounds: ClosedRange<Double> { 0.004...0.30 }

    /// Builds a well-formed, rounded quote from an agent's intent.
    ///
    /// - Parameters:
    ///   - center: where the agent thinks the contract is worth.
    ///   - bidHalfPct: half-spread on the bid side, as a fraction of center.
    ///   - askHalfPct: half-spread on the ask side.
    ///   - bidSize / askSize: contracts shown. Zero means "not quoting
    ///     that side".
    ///
    /// Guarantees the result is uncrossed, positive, and at least
    /// `minimumSpread` wide, so no downstream code has to defend itself.
    func buildQuote(center: Double,
                    bidHalfPct: Double,
                    askHalfPct: Double,
                    bidSize: Int,
                    askSize: Int,
                    stance: AgentStance,
                    rationale: String) -> AgentQuote {
        let safeCenter = max(0.05, center.isFinite ? center : 0.05)
        let bh = clampHalf(bidHalfPct)
        let ah = clampHalf(askHalfPct)

        var bid = safeCenter * (1 - bh)
        var ask = safeCenter * (1 + ah)

        // Never let rounding or a pathological input produce a crossed
        // or zero-width market.
        bid = max(0.05, bid)
        ask = max(bid + minimumSpread, ask)

        let q = Quote(bid: bid, ask: ask,
                      bidSize: max(0, bidSize),
                      askSize: max(0, askSize)).rounded()

        // Rounding to cents can re-cross a very tight market; widen the
        // offer by one tick if that happened.
        let safe = q.bid >= q.ask
            ? Quote(bid: q.bid, ask: q.bid + minimumSpread,
                    bidSize: q.bidSize, askSize: q.askSize).rounded()
            : q

        return AgentQuote(agentId: id, agentName: name, glyph: glyph,
                          tint: tint, quote: safe, stance: stance,
                          rationale: rationale)
    }

    private func clampHalf(_ x: Double) -> Double {
        guard x.isFinite else { return halfSpreadBounds.lowerBound }
        return min(max(x, halfSpreadBounds.lowerBound), halfSpreadBounds.upperBound)
    }

    /// Formats a signed sentiment number the way the desk prints it.
    func fmt(_ x: Double) -> String { String(format: "%+.2f", x) }
    func pct(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }
}

// MARK: - 1. Momentum

/// Leans into the crowd. When sentiment is bullish for this side it
/// raises its center, tightens its bid, and shows more size where it
/// wants to accumulate. This is the agent that makes a hyped movie's
/// Calls climb before anything has actually happened.
struct MomentumAgent: MarketMakingAgent {
    let id = "momentum"
    let name = "Trend Rider"
    let blurb = "Leans into the crowd. Buys strength, sells weakness."
    let glyph = "chart.line.uptrend.xyaxis"
    let tint: AgentTint = .bull

    /// How far the center moves at full conviction sentiment.
    var lean: Double = 0.06
    var baseHalfSpread: Double = 0.025
    var baseSize: Int = 10

    func quote(_ ctx: QuoteContext, rng: inout SeededGenerator) -> AgentQuote {
        let d = ctx.directional
        let conviction = ctx.pulse.confidence
        let effective = d * conviction

        // Center moves with the crowd, then gets shaded against the
        // desk's own inventory.
        let center = ctx.fairValue
            * (1 + lean * effective)
            * (1 - 0.02 * ctx.inventoryPressure)

        // Tighten the side we want, back away from the side we don't.
        let width = baseHalfSpread
            * (1 + 0.6 * ctx.pulse.dispersion)
            * (1 + 0.4 * ctx.expiryPressure)
        let bidHalf = width * (1 - 0.5 * effective) + rng.jitter(0.002)
        let askHalf = width * (1 + 0.5 * effective) + rng.jitter(0.002)

        let sizeScale = 0.6 + 0.8 * ctx.pulse.volume
        let bidSize = max(1, Int((Double(baseSize) * sizeScale * (1 + effective)).rounded()))
        let askSize = max(1, Int((Double(baseSize) * sizeScale * (1 - effective)).rounded()))

        let stance: AgentStance = abs(effective) < 0.08
            ? .balanced
            : (effective > 0 ? .bidding : .offering)

        let rationale: String = {
            if abs(effective) < 0.08 {
                return "Crowd read \(fmt(d)) is too weak to lean on. Quoting flat."
            }
            if effective > 0 {
                return "Crowd \(fmt(d)) with \(pct(conviction)) conviction — lifting my bid, showing \(bidSize) up."
            }
            return "Crowd \(fmt(d)) against this side — dropping my offer, showing \(askSize) down."
        }()

        return buildQuote(center: center, bidHalfPct: bidHalf, askHalfPct: askHalf,
                          bidSize: bidSize, askSize: askSize,
                          stance: stance, rationale: rationale)
    }
}

// MARK: - 2. Contrarian

/// Fades extremes. Below its threshold it quotes a lazy, wide,
/// symmetric market and mostly gets out of the way. Once the crowd goes
/// euphoric or panicked it takes the other side hard — which is what
/// stops a single viral trailer from repricing a chain to infinity.
struct ContrarianAgent: MarketMakingAgent {
    let id = "contrarian"
    let name = "Fade Desk"
    let blurb = "Sells euphoria, buys panic. Ignores everything in between."
    let glyph = "arrow.uturn.backward.circle"
    let tint: AgentTint = .bear

    /// |sentiment| below this and the agent stays passive.
    var threshold: Double = 0.35
    var fadeLean: Double = 0.05
    var baseHalfSpread: Double = 0.03
    var baseSize: Int = 8

    func quote(_ ctx: QuoteContext, rng: inout SeededGenerator) -> AgentQuote {
        let d = ctx.directional
        let magnitude = abs(d)

        guard magnitude >= threshold else {
            // Passive mode: wide, symmetric, small. Present but not
            // competing for the top of book.
            let half = baseHalfSpread * 1.8
                * (1 + 0.4 * ctx.expiryPressure)
                + rng.jitter(0.003)
            return buildQuote(center: ctx.fairValue,
                              bidHalfPct: half, askHalfPct: half,
                              bidSize: baseSize / 2, askSize: baseSize / 2,
                              stance: .balanced,
                              rationale: "Crowd \(fmt(d)) is inside my \(String(format: "%.2f", threshold)) band. Nothing to fade.")
        }

        // Excess is how far past the threshold the crowd has run,
        // rescaled so it reaches 1.0 at the extreme.
        let excess = (magnitude - threshold) / max(0.01, 1 - threshold)
        let signedExcess = excess * (d > 0 ? 1 : -1)

        // Push the center *against* the crowd.
        let center = ctx.fairValue * (1 - fadeLean * signedExcess)

        let width = baseHalfSpread
            * (1 + 0.5 * ctx.pulse.dispersion)
            * (1 + 0.4 * ctx.expiryPressure)
        // Tighten the side we are taking. Crowd bullish → we offer.
        let bidHalf = width * (1 + 0.6 * signedExcess) + rng.jitter(0.002)
        let askHalf = width * (1 - 0.6 * signedExcess) + rng.jitter(0.002)

        let aggression = 1 + 1.2 * excess
        let bidSize = Int((Double(baseSize) * (signedExcess < 0 ? aggression : 0.5)).rounded())
        let askSize = Int((Double(baseSize) * (signedExcess > 0 ? aggression : 0.5)).rounded())

        let rationale = signedExcess > 0
            ? "Crowd euphoric at \(fmt(d)). Fading it — offering \(max(1, askSize)) down."
            : "Crowd capitulating at \(fmt(d)). Stepping in — bidding \(max(1, bidSize)) up."

        return buildQuote(center: center, bidHalfPct: bidHalf, askHalfPct: askHalf,
                          bidSize: max(1, bidSize), askSize: max(1, askSize),
                          stance: signedExcess > 0 ? .offering : .bidding,
                          rationale: rationale)
    }
}

// MARK: - 3. Anchor

/// The baseline liquidity provider. Quotes around the rolling S/R mid
/// and ignores the sentiment *level* entirely — it only widens when the
/// crowd fragments. Its job is to guarantee the book is never empty, so
/// it always shows the largest symmetric size on the desk.
struct AnchorAgent: MarketMakingAgent {
    let id = "anchor"
    let name = "The Anchor"
    let blurb = "Always two-sided around support and resistance. Never chases."
    let glyph = "scalemass"
    let tint: AgentTint = .steel

    var baseHalfSpread: Double = 0.035
    var baseSize: Int = 18

    func quote(_ ctx: QuoteContext, rng: inout SeededGenerator) -> AgentQuote {
        // Anchor on the S/R midpoint when the tape supports one, but
        // never let it drift more than 8% from theoretical value.
        let anchor: Double = {
            guard let lvl = ctx.level, lvl.mid > 0 else { return ctx.fairValue }
            let lo = ctx.fairValue * 0.92
            let hi = ctx.fairValue * 1.08
            return min(max(lvl.mid, lo), hi)
        }()

        let center = anchor * (1 - 0.03 * ctx.inventoryPressure)

        // Dispersion and imminent expiry are the only things that move
        // this agent's width.
        let half = baseHalfSpread
            * (1 + 0.9 * ctx.pulse.dispersion)
            * (1 + 0.5 * ctx.expiryPressure)
            + rng.jitter(0.002)

        // Size shrinks when the crowd is fragmented, but never to zero.
        let sizeScale = max(0.4, 1 - 0.5 * ctx.pulse.dispersion)
        let size = max(4, Int((Double(baseSize) * sizeScale).rounded()))

        let rationale: String = {
            if ctx.level != nil {
                return "Anchored on the S/R mid at \(String(format: "%.2f", anchor)). \(size) up, \(size) down."
            }
            return "No tape yet — anchoring on theoretical \(String(format: "%.2f", anchor)). \(size) each way."
        }()

        return buildQuote(center: center, bidHalfPct: half, askHalfPct: half,
                          bidSize: size, askSize: size,
                          stance: .balanced, rationale: rationale)
    }
}

// MARK: - 4. Velocity scalper

/// Trades the *derivative* of sentiment rather than its level. In calm
/// tape it is the tightest agent on the desk and sets the inside market.
/// The instant the narrative flips it widens violently and, past its
/// panic threshold, stops quoting the side it would be run over on.
struct VelocityScalperAgent: MarketMakingAgent {
    let id = "scalper"
    let name = "Tape Scalper"
    let blurb = "Tightest market in calm tape. First to vanish in a shock."
    let glyph = "bolt.horizontal.circle"
    let tint: AgentTint = .gold

    var lean: Double = 0.04
    var baseHalfSpread: Double = 0.014
    var baseSize: Int = 6
    /// |velocity| beyond which it pulls the exposed side entirely.
    var panicThreshold: Double = 0.55

    func quote(_ ctx: QuoteContext, rng: inout SeededGenerator) -> AgentQuote {
        let dv = ctx.directionalVelocity
        let speed = abs(ctx.pulse.velocity)

        let center = ctx.fairValue * (1 + lean * dv)

        // Width is dominated by how fast the story is moving.
        let half = baseHalfSpread
            * (1 + 3.0 * speed)
            * (1 + 0.6 * ctx.expiryPressure)
            + rng.jitter(0.0015)

        var bidSize = baseSize
        var askSize = baseSize
        var stance: AgentStance = .balanced
        var rationale = "Tape is quiet. Tightest market on the desk at \(pct(half * 2)) wide."

        if speed > panicThreshold {
            // Pull the side that a fast move would run through. Rising
            // sentiment burns the offer; falling sentiment burns the bid.
            if dv > 0 {
                askSize = 0
                stance = .steppingAway
                rationale = "Sentiment ripping \(fmt(ctx.pulse.velocity)) — pulling my offer, I'm not getting picked off."
            } else {
                bidSize = 0
                stance = .steppingAway
                rationale = "Sentiment collapsing \(fmt(ctx.pulse.velocity)) — pulling my bid until it settles."
            }
        } else if speed > 0.2 {
            stance = dv > 0 ? .bidding : .offering
            rationale = "Momentum \(fmt(ctx.pulse.velocity)) — widened to \(pct(half * 2)) and skewed with the move."
        }

        return buildQuote(center: center,
                          bidHalfPct: half * (1 - 0.3 * dv),
                          askHalfPct: half * (1 + 0.3 * dv),
                          bidSize: bidSize, askSize: askSize,
                          stance: stance, rationale: rationale)
    }
}

// MARK: - 5. Vol breaker

/// The risk desk. It has no directional opinion at all — its center is
/// always theoretical value. What it trades is *disagreement*: the more
/// the crowd fragments, the wider it quotes and the less size it shows,
/// and on a genuine shock it goes dark entirely. This is the agent that
/// turns a viral controversy into a visibly fractured market.
struct VolBreakerAgent: MarketMakingAgent {
    let id = "volbreaker"
    let name = "Vol Breaker"
    let blurb = "No opinion on direction. Prices disagreement and shock risk."
    let glyph = "waveform.path.ecg"
    let tint: AgentTint = .violet

    var baseHalfSpread: Double = 0.028
    var dispersionWeight: Double = 0.11
    var baseSize: Int = 12

    func quote(_ ctx: QuoteContext, rng: inout SeededGenerator) -> AgentQuote {
        let disp = ctx.pulse.dispersion
        let vol = ctx.pulse.volume

        // Go dark on a shock. A risk desk that keeps quoting through a
        // gap is a risk desk that loses money.
        if ctx.pulse.isShock {
            return buildQuote(center: ctx.fairValue,
                              bidHalfPct: 0.30, askHalfPct: 0.30,
                              bidSize: 0, askSize: 0,
                              stance: .steppingAway,
                              rationale: "Velocity \(fmt(ctx.pulse.velocity)) is a gap. No market until the tape settles.")
        }

        // Loud + united narrows this agent; quiet + fractured widens it.
        let half = (baseHalfSpread + dispersionWeight * disp)
            * (1 - 0.35 * max(0, vol - disp))
            * (1 + 0.5 * ctx.expiryPressure)
            + rng.jitter(0.002)

        let size = max(1, Int((Double(baseSize) * (1 - 0.7 * disp)).rounded()))

        let rationale: String = {
            if disp > 0.6 {
                return "Crowd is split \(pct(disp)) — widening to \(pct(half * 2)) and cutting size to \(size)."
            }
            if ctx.pulse.isConviction {
                return "Loud and united — comfortable at \(pct(half * 2)) wide, \(size) each way."
            }
            return "Dispersion \(pct(disp)). Quoting \(pct(half * 2)) wide, no directional view."
        }()

        return buildQuote(center: ctx.fairValue,
                          bidHalfPct: half, askHalfPct: half,
                          bidSize: size, askSize: size,
                          stance: .balanced, rationale: rationale)
    }
}

// MARK: - Roster

enum AgentRoster {
    /// The default desk. Order matters only for display.
    static func standard() -> [MarketMakingAgent] {
        [
            AnchorAgent(),
            MomentumAgent(),
            ContrarianAgent(),
            VelocityScalperAgent(),
            VolBreakerAgent()
        ]
    }
}
