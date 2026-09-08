import SwiftUI

/// The market-making desk for a single contract.
///
/// This is the screen that shows *why* a price is what it is: the crowd
/// read at the top, every agent's live market in the middle, and the
/// chatter that moved them at the bottom. Nothing here is decorative —
/// every number on the page is an input to the price above it.
struct TradingDeskView: View {
    let contract: Contract
    let movie: Movie

    @EnvironmentObject var market: MarketService
    @ObservedObject private var sentiment = SentimentEngine.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.lg) {
                if let book = market.book(contractId: contract.id) {
                    crowdCard(book: book)
                    InsideMarketCard(book: book)
                    imbalanceCard(book: book)
                    agentsSection(book: book)
                } else {
                    warmingUp
                }
                chatterSection
                explainer
            }
            .padding(Theme.Space.lg)
        }
        .background(Theme.stageBlack.opacity(0.03).ignoresSafeArea())
        .navigationTitle("Trading Desk")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Crowd

    private func crowdCard(book: QuoteBook) -> some View {
        VStack(spacing: Theme.Space.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(movie.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(contract.side.display) $\(Int(contract.strikeMillions))M")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(contract.side == .call ? Theme.bull : Theme.bear)
                }
                Spacer()
                LivePulse()
            }

            SentimentGauge(pulse: book.pulse)

            Text(book.pulse.mood.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Theme.Space.md) {
                metric("Conviction", pct(book.pulse.confidence),
                       tint: book.pulse.confidence > 0.5 ? Theme.bull : Theme.neutral)
                metric("Chatter", pct(book.pulse.volume), tint: Theme.marqueeGold)
                metric("Split", pct(book.pulse.dispersion),
                       tint: book.pulse.dispersion > 0.6 ? Theme.bear : Theme.neutral)
                metric("Momentum", String(format: "%+.2f", book.pulse.velocity),
                       tint: book.pulse.isShock ? .orange : Theme.neutral)
            }

            let samples = sentiment.scoreHistory(for: movie.id)
            if samples.count >= 2 {
                SentimentSparkline(samples: samples)
                    .padding(.top, Theme.Space.xs)
            }

            if book.pulse.isShock {
                shockBanner
            }
        }
        .padding(Theme.Space.md)
        .glassSurface(radius: Theme.Radius.lg,
                      stroke: book.pulse.mood.color.opacity(0.30))
    }

    private var shockBanner: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                .foregroundStyle(.orange)
            Text("Narrative is moving fast. Agents widen or pull quotes to avoid getting picked off, so spreads blow out until it settles.")
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm)
            .fill(Color.orange.opacity(0.14)))
    }

    private func metric(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    // MARK: - Imbalance

    private func imbalanceCard(book: QuoteBook) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("Where the size is")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(book.headline)
                    .font(.caption2)
                    .foregroundStyle(book.nbbo.liquidityGrade.color)
            }
            ImbalanceBar(imbalance: book.nbbo.imbalance)
            HStack {
                Text("\(book.nbbo.askSize) offered")
                    .font(.caption2).foregroundStyle(Theme.bear)
                Spacer()
                Text("\(book.nbbo.bidSize) bid")
                    .font(.caption2).foregroundStyle(Theme.bull)
            }
            Text(book.nbbo.liquidityGrade.blurb)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Space.md)
        .glassSurface(radius: Theme.Radius.md)
    }

    // MARK: - Agents

    private func agentsSection(book: QuoteBook) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("The desk")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(book.activeAgents.count) of \(book.quotes.count) quoting")
                    .font(.caption2)
                    .foregroundStyle(book.steppedAway.isEmpty ? Color.secondary : Color.orange)
            }

            let maxSize = book.quotes.reduce(1) { max($0, max($1.bidSize, $1.askSize)) }

            VStack(spacing: 0) {
                ForEach(Array(book.quotes.enumerated()), id: \.element.agentId) { idx, q in
                    AgentQuoteRow(
                        quote: q,
                        maxSize: maxSize,
                        isBestBid: q.bidSize > 0 && q.agentName == book.bestBidAgent,
                        isBestAsk: q.askSize > 0 && q.agentName == book.bestAskAgent
                    )
                    if idx < book.quotes.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .padding(Theme.Space.md)
        .glassSurface(radius: Theme.Radius.md)
    }

    // MARK: - Chatter

    private var chatterSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("What moved it")
                .font(.subheadline.weight(.semibold))

            let items = Array(sentiment.chatter(for: movie.id).prefix(12))
            if items.isEmpty {
                Text("No chatter on \(movie.title) yet. The desk is quoting off its standing view.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { event in
                    SentimentEventRow(event: event)
                    if event.id != items.last?.id { Divider().opacity(0.3) }
                }
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: Theme.Radius.md)
    }

    // MARK: - Explainer

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Label("How this price gets made", systemImage: "questionmark.circle")
                .font(.subheadline.weight(.semibold))
            explainRow("1", "Crowd read",
                       "Trailer engagement, mention volume, reviews, Hot Takes and real order flow blend into one score from -1 to +1.")
            explainRow("2", "Five agents quote it",
                       "Each has a different strategy. One chases the crowd, one fades it, one anchors on support and resistance, one trades momentum, one prices pure disagreement.")
            explainRow("3", "Best prices win",
                       "The highest bid and the lowest offer across all five become the market. When they agree the spread is tight. When sentiment splits them it blows out.")
            explainRow("4", "You pay the spread",
                       "Buying lifts the offer, selling hits the bid. The gap between them is what the desk earns for standing there.")
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: Theme.Radius.md)
    }

    private func explainRow(_ n: String, _ head: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text(n)
                .font(.caption2.weight(.heavy))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Theme.marqueeGold.opacity(0.25)))
                .foregroundStyle(Theme.marqueeGold)
            VStack(alignment: .leading, spacing: 2) {
                Text(head).font(.caption.weight(.semibold))
                Text(body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Empty

    private var warmingUp: some View {
        VStack(spacing: Theme.Space.sm) {
            ProgressView()
            Text("Agents are warming up their quotes…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.xl)
        .glassSurface(radius: Theme.Radius.md)
    }

    private func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
}

// MARK: - Movie-level desk summary

/// Compact desk roll-up for a whole movie, shown on the movie detail
/// screen above the chain.
struct DeskSummaryCard: View {
    let movieId: String
    @EnvironmentObject var market: MarketService

    var body: some View {
        if let summary = market.deskSummary(movieId: movieId) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    Label("Market makers", systemImage: "person.3.sequence.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.marqueeGold)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: summary.pulse.mood.glyph)
                        Text(summary.pulse.mood.label)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(summary.pulse.mood.color)
                }

                Text(summary.headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Space.lg) {
                    stat("Avg spread", String(format: "%.1f%%", summary.averageSpreadPct * 100),
                         tint: summary.grade.color)
                    stat("Lines quoted", "\(summary.contractsQuoted)", tint: .secondary)
                    if summary.steppedAwayCount > 0 {
                        stat("Pulled", "\(summary.steppedAwayCount)", tint: .orange)
                    }
                }
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(radius: Theme.Radius.md,
                          stroke: summary.grade.color.opacity(0.25))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Market maker desk. \(summary.headline) Average spread \(String(format: "%.1f", summary.averageSpreadPct * 100)) percent across \(summary.contractsQuoted) lines.")
        }
    }

    private func stat(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}
