import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompleted: Bool
    @State private var page: Int = 0
    @State private var showFullGuide = false
    /// The tour shows real movies from the live Slate, so it never goes
    /// stale. The only fixed example is a real, finished result.
    @ObservedObject private var market = MarketService.shared

    private let lastPage = 8

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomeSlide.tag(0)
                pickMovieSlide.tag(1)
                pickSideSlide.tag(2)
                buySlide.tag(3)
                trackSlide.tag(4)
                settleSlide.tag(5)
                weekSlide.tag(6)
                rulesSlide.tag(7)
                goalSlide.tag(8)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 10) {
                Button {
                    if page < lastPage {
                        withAnimation { page += 1 }
                    } else {
                        hasCompleted = true
                    }
                } label: {
                    Text(page < lastPage ? "Next" : "Start trading")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .primaryActionStyle()
                .controlSize(.large)
                .accessibilityIdentifier("tour.next")

                HStack(spacing: 24) {
                    Button("Read the full guide") { showFullGuide = true }
                    if page < lastPage {
                        Button("Skip") { hasCompleted = true }
                            .accessibilityIdentifier("tour.skip")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showFullGuide) {
            NavigationStack { LearnView() }
        }
    }

    // MARK: - Slides

    private var welcomeSlide: some View {
        slide(step: nil,
              emoji: "🎬",
              title: "Call the opening weekend.",
              body: "Predict how much upcoming movies will earn in their first weekend in U.S. theaters. The movies come straight from the box-office release calendars, and every trade settles on the real reported number.\n\nBoxCall is a free-to-play game. Reel Coins are play money — they can't be bought as a stake, cashed out, or exchanged for anything real.")
    }

    private var pickMovieSlide: some View {
        slide(step: 1,
              tab: ("film", "Now Showing"),
              title: "Pick a movie.",
              body: "Now Showing lists every wide release opening in the next 90 days — new ones appear automatically as studios date them. The big number is the market's current prediction for the opening weekend.") {
            MockCard {
                VStack(spacing: 8) {
                    if tourFilms.isEmpty {
                        mockMovieRow(emoji: "🎬", title: "Next week's opener", days: 7, implied: 30, highlighted: true)
                    } else {
                        ForEach(Array(tourFilms.enumerated()), id: \.element.id) { index, film in
                            mockMovieRow(emoji: film.posterEmoji, title: film.title,
                                         days: film.daysToRelease,
                                         implied: Int(market.impliedConsensus(for: film.id).rounded()),
                                         highlighted: index == 0)
                        }
                    }
                }
            }
        }
    }

    private var pickSideSlide: some View {
        slide(step: 2,
              tab: nil,
              title: "Bigger or smaller?",
              body: "Tap a movie and pick a dollar line — the strike. Then choose a side.") {
            HStack(spacing: 10) {
                sideCard(color: .green, icon: "arrow.up.right.circle.fill",
                         headline: "BIGGER", tag: "CALL",
                         detail: "Wins if it opens ABOVE your line.")
                sideCard(color: .red, icon: "arrow.down.right.circle.fill",
                         headline: "SMALLER", tag: "PUT",
                         detail: "Wins if it opens BELOW your line.")
            }
            .padding(.horizontal, 24)
        }
    }

    private var buySlide: some View {
        let example = exampleTrade
        return slide(step: 3,
              tab: nil,
              title: "Buy your position.",
              body: "Choose how many contracts and tap Buy. The price you pay is the most you can ever lose on that trade.") {
            MockCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(example.emoji) \(example.title)").font(.subheadline.weight(.semibold))
                        Spacer()
                        mockTag("CALL", .green)
                    }
                    mockLine("Strike", "$\(example.strike)M")
                    mockLine("Quantity", "5")
                    mockLine("Total cost", String(format: "%.2f RC", example.cost))
                    mockLine("Max loss", String(format: "%.2f RC", example.cost), valueColor: .orange)
                    Text("Buy")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.85)))
                        .foregroundStyle(.black)
                }
            }
        }
    }

    private var trackSlide: some View {
        let example = exampleTrade
        return slide(step: 4,
              tab: ("chart.line.uptrend.xyaxis", "Positions"),
              title: "Watch it move. Sell any time.",
              body: "Prices shift while the market buys and sells, your trades included. Close a position whenever you like until the movie opens. Trading locks at midnight on opening day — usually Friday, sometimes Wednesday or Thursday. If you hold it, we'll remind you at 6 PM the night before.") {
            MockCard {
                VStack(spacing: 8) {
                    mockPositionRow(emoji: example.emoji, title: example.title,
                                    side: "CALL $\(example.strike)M", pnl: 18.2)
                    HStack(spacing: 6) {
                        Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
                        Text("\(example.title) opens tomorrow — trading locks at midnight.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var settleSlide: some View {
        slide(step: 5,
              tab: nil,
              title: "Results on Sunday.",
              body: "Sunday afternoon the studios report the weekend. BoxCall settles every position on that estimate automatically — the same number for every player. A CALL pays 1 Reel Coin per contract for every $1M the opening lands above your line; a PUT, for every $1M below.") {
            MockCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A REAL RESULT · SEPT 18–20, 2026")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Resident Evil opened at $60.15M").font(.subheadline.weight(.semibold))
                    }
                    Text("A 5-contract CALL at $40M finished $20.15M in the money.")
                        .font(.caption).foregroundStyle(.secondary)
                    mockLine("Payout", "+100.75 RC", valueColor: .green)
                }
            }
        }
    }

    private var weekSlide: some View {
        slide(step: nil,
              tab: nil,
              title: "How each week works.",
              body: "You start with a 1,000 Reel Coin stake. Play money only — it can't be cashed out.") {
            MockCard {
                VStack(alignment: .leading, spacing: 12) {
                    weekRow(day: "FRI", icon: "lock.fill", color: .orange,
                            text: "The movie opens and trading on it locks. (A few open Wednesday or Thursday and lock that day.)")
                    weekRow(day: "SUN", icon: "checkmark.seal.fill", color: .red,
                            text: "Weekly reset: your 1,000 stake goes back — **you keep your profit**. Studios report the weekend and winners get paid.")
                    weekRow(day: "MON", icon: "arrow.clockwise.circle.fill", color: .green,
                            text: "**Everyone gets a fresh 1,000**, so a bad week never locks you out.")
                    Divider()
                    weekRow(day: "ALL", icon: "arrow.right.circle.fill", color: .blue,
                            text: "Trades on movies that haven't opened yet keep running right through the reset. **Profit is never reset.**")
                }
            }
        }
    }

    private var rulesSlide: some View {
        slide(step: nil,
              tab: nil,
              title: "Fair-play rules.",
              body: "A few things that keep every market honest.") {
            MockCard {
                VStack(alignment: .leading, spacing: 12) {
                    ruleRow(icon: "calendar.badge.clock", color: .blue,
                            title: "Release date moved?",
                            text: "Your trades carry over and trading stays open until the movie actually opens.")
                    ruleRow(icon: "arrow.uturn.backward.circle.fill", color: .green,
                            title: "Already opened in limited release?",
                            text: "Its result is known, so the market closes and every trade on it is refunded at cost.")
                    ruleRow(icon: "hourglass", color: .orange,
                            title: "No result reported?",
                            text: "If no number is published within three weeks of opening, the market settles on a simulated result so no one is left waiting.")
                    ruleRow(icon: "star.circle.fill", color: .purple,
                            title: "Subscriptions",
                            text: "They add tools and a badge — never Reel Coins. Everyone trades the same stake.")
                }
            }
        }
    }

    private func ruleRow(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.bold))
                Text(text).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var goalSlide: some View {
        slide(step: nil,
              tab: ("trophy", "Box Office"),
              title: "The goal: most profit.",
              body: "You compete against BoxCall's simulated league — automated traders marked SIM — and the leaderboard ranks by total profit. Profit earns ranks like Insider and Studio Head, and the top 5 get their movie review spotlighted on the home screen, #1 first.") {
            MockCard {
                VStack(alignment: .leading, spacing: 8) {
                    mockRankRow("🥇", "you", "Studio Head", "+3,410", highlighted: true)
                    mockRankRow("🥈", "popcornshark", "Studio Head", "+3,180", highlighted: false, simulated: true)
                    mockRankRow("🥉", "indieyoda", "Producer", "+1,905", highlighted: false, simulated: true)
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        mockTag("#1", .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\u{201C}Consensus is fifteen million light.\u{201D}")
                                .font(.caption.weight(.semibold))
                            Text("#1 trader @you · featured on the Marquee home screen")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Be #1 when the season ends to be crowned its Oracle. Replay this tour any time from Profile.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private func mockRankRow(_ medal: String, _ handle: String, _ rank: String, _ profit: String,
                             highlighted: Bool, simulated: Bool = false) -> some View {
        HStack {
            Text(medal)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text("@\(handle)").font(.subheadline.weight(highlighted ? .bold : .regular))
                        .foregroundStyle(highlighted ? Color.orange : .primary)
                    if simulated { SimulatedTag() }
                }
                Text(rank).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(profit).font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private func weekRow(day: String, icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(day)
                .font(.caption2.weight(.heavy).monospaced())
                .foregroundStyle(color)
                .frame(width: 32, alignment: .leading)
                .padding(.top, 2)
            Image(systemName: icon).foregroundStyle(color)
            Text(.init(text))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Live examples

    /// The two soonest movies still open for trading.
    private var tourFilms: [Movie] {
        Array(market.movies.filter(\.isTradingOpen).prefix(2))
    }

    /// A real contract on the soonest film: the CALL strike nearest the
    /// market's prediction, priced at the desk's ask (what a buy fills at)
    /// for 5 contracts.
    private var exampleTrade: (emoji: String, title: String, strike: Int, cost: Double) {
        guard let film = tourFilms.first else { return ("🎬", "Next week's opener", 30, 22.50) }
        let implied = market.impliedConsensus(for: film.id)
        let call = market.chain(for: film.id)
            .filter { $0.side == .call }
            .min { abs($0.strikeMillions - implied) < abs($1.strikeMillions - implied) }
        guard let call else { return (film.posterEmoji, film.title, Int(implied.rounded()), 22.50) }
        let ask = market.ask(contractId: call.id)
        return (film.posterEmoji, film.title, Int(call.strikeMillions), (ask > 0 ? ask : call.premium) * 5)
    }

    // MARK: - Slide scaffolding

    private func slide(step: Int?, emoji: String, title: String, body: String) -> some View {
        slide(step: step, tab: nil, title: title, body: body, header: {
            Text(emoji).scaledFont(72)
        }, extra: { EmptyView() })
    }

    private func slide<Extra: View>(step: Int?, tab: (icon: String, name: String)?,
                                    title: String, body: String,
                                    @ViewBuilder extra: () -> Extra) -> some View {
        slide(step: step, tab: tab, title: title, body: body, header: { EmptyView() }, extra: extra)
    }

    private func slide<Header: View, Extra: View>(step: Int?, tab: (icon: String, name: String)?,
                                                  title: String, body: String,
                                                  @ViewBuilder header: () -> Header,
                                                  @ViewBuilder extra: () -> Extra) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                header()
                if step != nil || tab != nil {
                    HStack(spacing: 8) {
                        if let step {
                            Text("STEP \(step) OF 5")
                                .font(.caption2.weight(.heavy))
                                .tracking(1.2)
                                .foregroundStyle(.orange)
                        }
                        if let tab {
                            Label(tab.name, systemImage: tab.icon)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Text(title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
            .padding(.top, 40)
            .padding(.bottom, 50)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Mock UI pieces

    private func mockMovieRow(emoji: String, title: String, days: Int, implied: Int, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Text(emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Label("\(days)d", systemImage: "clock")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("$\(implied)M").font(.headline.monospacedDigit())
                Text("predicted").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10)
            .stroke(highlighted ? Color.orange : .clear, lineWidth: 1.5))
    }

    private func sideCard(color: Color, icon: String, headline: String, tag: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title).foregroundStyle(color)
            Text(headline).font(.headline.weight(.heavy)).foregroundStyle(color)
            mockTag(tag, color)
            Text(detail)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35), lineWidth: 1))
    }

    private func mockPositionRow(emoji: String, title: String, side: String, pnl: Double) -> some View {
        HStack(spacing: 10) {
            Text(emoji).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(side).font(.caption2.weight(.bold))
                    .foregroundStyle(side.hasPrefix("CALL") ? .green : .red)
            }
            Spacer()
            Text(pnl, format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(pnl >= 0 ? .green : .red)
        }
    }

    private func mockTag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.25)))
            .foregroundStyle(color)
    }

    private func mockLine(_ label: String, _ value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(valueColor)
        }
    }
}

private struct MockCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
    }
}
