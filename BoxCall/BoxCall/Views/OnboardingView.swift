import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompleted: Bool
    @State private var page: Int = 0
    @State private var showFullGuide = false

    private let lastPage = 6

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
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)

                HStack(spacing: 24) {
                    Button("Read the full guide") { showFullGuide = true }
                    if page < lastPage {
                        Button("Skip") { hasCompleted = true }
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
              body: "Predict how much upcoming movies will earn in their first weekend. Be right, earn Reel Coins and climb the leaderboard.\n\nBoxCall is a free-to-play game. Reel Coins are play money — they can't be bought as a stake, cashed out, or exchanged for anything real.")
    }

    private var pickMovieSlide: some View {
        slide(step: 1,
              tab: ("film", "Now Showing"),
              title: "Pick a movie.",
              body: "The Now Showing tab lists every upcoming release. The big number is the crowd's current prediction for its opening weekend.") {
            MockCard {
                VStack(spacing: 8) {
                    mockMovieRow(emoji: "🧟", title: "Resident Evil", days: 3, implied: 45, highlighted: true)
                    mockMovieRow(emoji: "🎄", title: "Violent Night 2", days: 17, implied: 20, highlighted: false)
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
        slide(step: 3,
              tab: nil,
              title: "Buy your position.",
              body: "Choose how many contracts and tap Buy. The price you pay is the most you can ever lose on that trade.") {
            MockCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("🧟 Resident Evil").font(.subheadline.weight(.semibold))
                        Spacer()
                        mockTag("CALL", .green)
                    }
                    mockLine("Strike", "$40M")
                    mockLine("Quantity", "5")
                    mockLine("Total cost", "42.50 RC")
                    mockLine("Max loss", "42.50 RC", valueColor: .orange)
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
        slide(step: 4,
              tab: ("chart.line.uptrend.xyaxis", "Positions"),
              title: "Watch it move.",
              body: "Prices shift all week as other players trade and news breaks. Sell any time before the movie opens on Friday — then its contracts lock until results.") {
            MockCard {
                VStack(spacing: 8) {
                    mockPositionRow(emoji: "🧟", title: "Resident Evil", side: "CALL $40M", pnl: 18.2)
                    mockPositionRow(emoji: "🎄", title: "Violent Night 2", side: "PUT $22M", pnl: -3.4)
                }
            }
        }
    }

    private var settleSlide: some View {
        slide(step: 5,
              tab: nil,
              title: "Results on Monday.",
              body: "After opening weekend, BoxCall pulls the reported box-office number and settles every position automatically. Winners get paid for every $1M past their line.") {
            MockCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Resident Evil opened at $52M").font(.subheadline.weight(.semibold))
                    }
                    Text("Your CALL at $40M finished $12M in the money.")
                        .font(.caption).foregroundStyle(.secondary)
                    mockLine("Payout", "+60.00 RC", valueColor: .green)
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
                            text: "The movie opens. Trading on it locks.")
                    weekRow(day: "SUN", icon: "arrow.uturn.backward.circle.fill", color: .red,
                            text: "Weekly reset. Your 1,000 stake goes back — **you keep your profit**.")
                    weekRow(day: "MON", icon: "checkmark.seal.fill", color: .green,
                            text: "Results settle and winners get paid. **Everyone gets a fresh 1,000**, so a bad week never locks you out.")
                    Divider()
                    weekRow(day: "ALL", icon: "arrow.right.circle.fill", color: .blue,
                            text: "Trades on movies that haven't opened yet — like Avengers: Doomsday — keep running right through the reset.")
                }
            }
            Text("Wins earn XP, badges and a spot on the Box Office leaderboard. Replay this tour any time from Profile.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
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

    // MARK: - Slide scaffolding

    private func slide(step: Int?, emoji: String, title: String, body: String) -> some View {
        slide(step: step, tab: nil, title: title, body: body, header: {
            Text(emoji).font(.system(size: 72))
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
                if let step {
                    HStack(spacing: 8) {
                        Text("STEP \(step) OF 5")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(.orange)
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
