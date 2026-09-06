import SwiftUI

// MARK: - Palette bridge

extension AgentTint {
    var color: Color {
        switch self {
        case .bull:   return Theme.bull
        case .bear:   return Theme.bear
        case .gold:   return Theme.marqueeGold
        case .violet: return Color(red: 0.60, green: 0.44, blue: 0.93)
        case .steel:  return Color(red: 0.46, green: 0.58, blue: 0.72)
        }
    }
}

extension SentimentMood {
    var color: Color {
        switch self {
        case .euphoric: return Theme.bull
        case .bullish:  return Theme.bull.opacity(0.85)
        case .mixed:    return Theme.neutral
        case .bearish:  return Theme.bear.opacity(0.85)
        case .panicked: return Theme.bear
        }
    }
}

extension LiquidityGrade {
    var color: Color {
        switch self {
        case .deep:      return Theme.bull
        case .healthy:   return Theme.marqueeGold
        case .thin:      return .orange
        case .fractured: return Theme.bear
        }
    }
}

extension AgentStance {
    var color: Color {
        switch self {
        case .bidding:      return Theme.bull
        case .offering:     return Theme.bear
        case .balanced:     return Theme.neutral
        case .steppingAway: return .orange
        }
    }
}

// MARK: - Sentiment gauge

/// Half-circle gauge showing where the crowd sits, from panicked on the
/// left to euphoric on the right. The needle animates between readings,
/// and the arc thickens with the desk's confidence in the number.
struct SentimentGauge: View {
    let pulse: SentimentPulse
    var size: CGFloat = 148

    var body: some View {
        ZStack {
            Canvas { ctx, canvas in
                let rect = CGRect(origin: .zero, size: canvas)
                let center = CGPoint(x: rect.midX, y: rect.maxY - 6)
                let radius = min(rect.width / 2, rect.height) - 14
                guard radius > 0 else { return }

                // Background track.
                var track = Path()
                track.addArc(center: center, radius: radius,
                             startAngle: .degrees(180), endAngle: .degrees(360),
                             clockwise: false)
                ctx.stroke(track, with: .color(Color.primary.opacity(0.10)),
                           style: StrokeStyle(lineWidth: 12, lineCap: .round))

                // Live arc, sweeping out from top-center toward the mood.
                // 180 degrees is hard bearish, 270 neutral, 360 euphoric.
                let neutralDeg = 270.0
                let targetDeg = 270.0 + pulse.score * 90.0
                var live = Path()
                live.addArc(center: center, radius: radius,
                            startAngle: .degrees(min(neutralDeg, targetDeg)),
                            endAngle: .degrees(max(neutralDeg, targetDeg)),
                            clockwise: false)
                let width = 8 + 8 * pulse.confidence
                ctx.stroke(live, with: .color(mood.color),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))

                // Needle.
                let rad = CGFloat(Angle.degrees(targetDeg).radians)
                let tip = CGPoint(x: center.x + cos(rad) * (radius + 4),
                                  y: center.y + sin(rad) * (radius + 4))
                var needle = Path()
                needle.move(to: center)
                needle.addLine(to: tip)
                ctx.stroke(needle, with: .color(mood.color),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                ctx.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4,
                                                width: 8, height: 8)),
                         with: .color(mood.color))
            }
            .frame(width: size, height: size / 2 + 14)

            VStack(spacing: 1) {
                Text(String(format: "%+.2f", pulse.score))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(mood.color)
                Text(mood.label.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
            .offset(y: size / 5)
        }
        .animation(Theme.Motion.smooth, value: pulse.score)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crowd sentiment \(mood.label), score \(String(format: "%.2f", pulse.score)), confidence \(Int(pulse.confidence * 100)) percent")
    }

    private var mood: SentimentMood { pulse.mood }
}

// MARK: - Sentiment history line

/// Sparkline of the crowd score over time, with a zero line so bullish
/// and bearish stretches read at a glance.
struct SentimentSparkline: View {
    let samples: [SentimentSample]
    var height: CGFloat = 44

    var body: some View {
        Canvas { ctx, size in
            guard samples.count >= 2 else { return }

            // Fixed -1...1 domain so the shape means the same thing on
            // every movie, rather than auto-scaling to noise.
            func y(_ score: Double) -> CGFloat {
                size.height * CGFloat((1 - score) / 2)
            }
            let dx = size.width / CGFloat(samples.count - 1)

            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: y(0)))
            zero.addLine(to: CGPoint(x: size.width, y: y(0)))
            ctx.stroke(zero, with: .color(Color.primary.opacity(0.15)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            var line = Path()
            for (i, s) in samples.enumerated() {
                let pt = CGPoint(x: CGFloat(i) * dx, y: y(s.score))
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }

            let last = samples.last?.score ?? 0
            let tint: Color = last >= 0 ? Theme.bull : Theme.bear
            ctx.stroke(line, with: .color(tint),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            if let lastPoint = samples.indices.last {
                let pt = CGPoint(x: CGFloat(lastPoint) * dx, y: y(last))
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3,
                                                width: 6, height: 6)),
                         with: .color(tint))
            }
        }
        .frame(height: height)
        .accessibleChart(summary)
    }

    private var summary: String {
        guard let first = samples.first?.score, let last = samples.last?.score else {
            return "No sentiment history yet"
        }
        let dir = last >= first ? "rising" : "falling"
        return "Sentiment \(dir) from \(String(format: "%.2f", first)) to \(String(format: "%.2f", last))"
    }
}

// MARK: - Inside market

/// The headline bid / ask, with the size behind each side and the
/// spread between them.
struct InsideMarketCard: View {
    let book: QuoteBook

    var body: some View {
        HStack(spacing: 0) {
            sideColumn(label: "BID", price: book.nbbo.bid, size: book.nbbo.bidSize,
                       who: book.bestBidAgent, tint: Theme.bull, alignment: .leading)

            VStack(spacing: 2) {
                Text("SPREAD")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2f", book.nbbo.spread))
                    .font(.callout.weight(.bold).monospacedDigit())
                Text(String(format: "%.1f%%", book.nbbo.spreadPct * 100))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(book.nbbo.liquidityGrade.color)
            }
            .frame(maxWidth: .infinity)

            sideColumn(label: "ASK", price: book.nbbo.ask, size: book.nbbo.askSize,
                       who: book.bestAskAgent, tint: Theme.bear, alignment: .trailing)
        }
        .padding(.vertical, Theme.Space.md)
        .padding(.horizontal, Theme.Space.md)
        .glassSurface(radius: Theme.Radius.md,
                      stroke: book.nbbo.liquidityGrade.color.opacity(0.35))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Inside market. Bid \(String(format: "%.2f", book.nbbo.bid)) for \(book.nbbo.bidSize). Ask \(String(format: "%.2f", book.nbbo.ask)) for \(book.nbbo.askSize). Spread \(String(format: "%.2f", book.nbbo.spread)).")
    }

    private func sideColumn(label: String, price: Double, size: Int,
                            who: String?, tint: Color,
                            alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(.secondary)
            Text(size > 0 ? String(format: "%.2f", price) : "—")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(size > 0 ? tint : Color.secondary)
                .contentTransition(.numericText())
            Text(size > 0 ? "\(size) up" : "no size")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            if let who, size > 0 {
                Text(who)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

// MARK: - Imbalance bar

/// Which side the desk's size is stacked on. Full left = all offers,
/// full right = all bids.
struct ImbalanceBar: View {
    let imbalance: Double
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fraction = CGFloat((imbalance + 1) / 2)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.bear.opacity(0.28))
                Capsule().fill(Theme.bull.opacity(0.85))
                    .frame(width: max(2, w * fraction))
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 1)
                    .offset(x: w / 2)
            }
        }
        .frame(height: height)
        .animation(Theme.Motion.smooth, value: imbalance)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(imbalance >= 0
            ? "Book imbalance \(Int(abs(imbalance) * 100)) percent toward buyers"
            : "Book imbalance \(Int(abs(imbalance) * 100)) percent toward sellers")
    }
}

// MARK: - Agent row

/// One agent's live market, with the reason it is quoting that way.
struct AgentQuoteRow: View {
    let quote: AgentQuote
    /// Widest size on the desk, used to scale the depth bars.
    let maxSize: Int
    let isBestBid: Bool
    let isBestAsk: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: quote.glyph)
                    .font(.callout)
                    .foregroundStyle(quote.tint.color)
                    .frame(width: 22)

                Text(quote.agentName)
                    .font(.subheadline.weight(.semibold))

                stanceBadge

                Spacer(minLength: 4)

                priceBlock
            }

            depthBars

            Text(quote.rationale)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Space.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y)
    }

    private var stanceBadge: some View {
        Text(quote.stance.label)
            .font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(quote.stance.color.opacity(0.20)))
            .foregroundStyle(quote.stance.color)
    }

    @ViewBuilder
    private var priceBlock: some View {
        HStack(spacing: 6) {
            price(quote.bid, size: quote.bidSize, tint: Theme.bull, isBest: isBestBid)
            Text("/").font(.caption2).foregroundStyle(.tertiary)
            price(quote.ask, size: quote.askSize, tint: Theme.bear, isBest: isBestAsk)
        }
    }

    private func price(_ value: Double, size: Int, tint: Color, isBest: Bool) -> some View {
        Text(size > 0 ? String(format: "%.2f", value) : "—")
            .font(.caption.weight(isBest ? .bold : .regular).monospacedDigit())
            .foregroundStyle(size > 0 ? tint : Color.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isBest && size > 0 ? tint.opacity(0.18) : .clear)
            )
    }

    private var depthBars: some View {
        HStack(spacing: 3) {
            // Bid depth grows leftward, ask depth rightward, so the row
            // reads like a two-sided ladder.
            bar(size: quote.bidSize, tint: Theme.bull, alignment: .trailing)
            bar(size: quote.askSize, tint: Theme.bear, alignment: .leading)
        }
        .frame(height: 6)
    }

    private func bar(size: Int, tint: Color, alignment: Alignment) -> some View {
        GeometryReader { geo in
            let fraction = maxSize > 0
                ? CGFloat(min(size, maxSize)) / CGFloat(maxSize)
                : 0
            ZStack(alignment: alignment) {
                Capsule().fill(Color.primary.opacity(0.06))
                Capsule().fill(tint.opacity(0.65))
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
    }

    private var a11y: String {
        guard quote.isQuoting else {
            return "\(quote.agentName) stepped away. \(quote.rationale)"
        }
        let bidPart = quote.bidSize > 0
            ? "bids \(String(format: "%.2f", quote.bid)) for \(quote.bidSize)"
            : "no bid"
        let askPart = quote.askSize > 0
            ? "offers \(String(format: "%.2f", quote.ask)) for \(quote.askSize)"
            : "no offer"
        return "\(quote.agentName), \(quote.stance.label). \(bidPart), \(askPart). \(quote.rationale)"
    }
}

// MARK: - Compact strip for the trade sheet

/// One-line bid / ask readout with the crowd mood, small enough to sit
/// inside a Form section.
struct QuoteStrip: View {
    let book: QuoteBook

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text("BID").font(.system(size: 8, weight: .heavy)).foregroundStyle(.secondary)
                Text(String(format: "%.2f", book.nbbo.bid))
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.bull)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("ASK").font(.system(size: 8, weight: .heavy)).foregroundStyle(.secondary)
                Text(String(format: "%.2f", book.nbbo.ask))
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.bear)
            }

            Divider().frame(height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(book.nbbo.liquidityGrade.label.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(book.nbbo.liquidityGrade.color)
                Text(String(format: "%.1f%% wide", book.nbbo.spreadPct * 100))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: book.pulse.mood.glyph)
                    .font(.caption2)
                Text(book.pulse.mood.label)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(book.pulse.mood.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Market \(String(format: "%.2f", book.nbbo.bid)) bid, \(String(format: "%.2f", book.nbbo.ask)) ask. \(book.nbbo.liquidityGrade.label) liquidity. Crowd \(book.pulse.mood.label).")
    }
}

// MARK: - Chatter row

/// One item from the sentiment feed.
struct SentimentEventRow: View {
    let event: SentimentEvent

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: event.source.glyph)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.text)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.source.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Text(String(format: "%+.2f", event.impact))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.source.label). \(event.text). Impact \(String(format: "%.2f", event.impact)).")
    }

    private var tint: Color {
        if abs(event.impact) < 0.08 { return Theme.neutral }
        return event.impact > 0 ? Theme.bull : Theme.bear
    }
}
