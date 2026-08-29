import SwiftUI

/// Plain-English "here's what this specific trade actually does" —
/// shown at the top of every TradeSheet, above the order form.
/// The first time a user opens a Call (or a Put), a full-screen
/// tutorial version fires so the concept is spelled out before
/// they can hit Buy. Subsequent trades keep the compact card.
struct ScenarioPrimer: View {
    let contract: Contract
    let movie: Movie
    let quantity: Int
    let liveMark: Double

    private var totalCost: Double { liveMark * Double(quantity) }
    private var breakEven: Double {
        contract.side == .call
            ? contract.strikeMillions + liveMark / contract.multiplier
            : contract.strikeMillions - liveMark / contract.multiplier
    }
    private var payoutPerDollar: Double {
        contract.multiplier * Double(quantity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBadge
            plainEnglishTLDR
            youAreBuyingLine
            Divider().padding(.vertical, 2)
            winCondition
            loseCondition
            rewardLine
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(sideColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(sideColor.opacity(0.35), lineWidth: 1)
        )
    }

    /// The 8-year-old-can-understand version, in one sentence.
    private var plainEnglishTLDR: some View {
        let overUnder = contract.side == .call ? "over" : "under"
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(sideColor)
                .font(.caption)
                .padding(.top, 2)
            Text(.init("**In plain English:** you're betting **\(movie.title)** opens **\(overUnder) $\(Int(contract.strikeMillions)) million** this weekend."))
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.9))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
    }

    private var sideColor: Color { contract.side == .call ? .green : .red }

    private var headerBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: contract.side == .call ? "arrow.up.right.circle.fill"
                                                      : "arrow.down.right.circle.fill")
                .foregroundStyle(sideColor)
            Text(contract.side.plain)      // "BIGGER" / "SMALLER"
                .font(.caption.weight(.heavy))
                .foregroundStyle(sideColor)
            Text("opening than the strike")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(contract.side.display)    // technical CALL/PUT chip
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(sideColor.opacity(0.25)))
                .foregroundStyle(sideColor)
        }
    }

    private var youAreBuyingLine: some View {
        Text("You're buying **\(quantity) \(contract.side.display)\(quantity == 1 ? "" : "S")** at the **$\(Int(contract.strikeMillions))M** strike on **\(movie.title)**, for a total of **\(totalCost, specifier: "%.2f") RC**.")
            .font(.callout)
    }

    @ViewBuilder
    private var winCondition: some View {
        outcomeRow(
            icon: "checkmark.circle.fill",
            color: .green,
            head: "You WIN if…",
            body: contract.side == .call
                ? "\(movie.title) opens **above $\(Int(contract.strikeMillions))M** this weekend. Every $1M above the strike pays you \(Int(payoutPerDollar)) RC."
                : "\(movie.title) opens **below $\(Int(contract.strikeMillions))M** this weekend. Every $1M below the strike pays you \(Int(payoutPerDollar)) RC.",
            highlight: "Break-even at $\(breakEven, specifier: "%.1f")M — above/below that is pure profit."
        )
    }

    @ViewBuilder
    private var loseCondition: some View {
        outcomeRow(
            icon: "xmark.circle.fill",
            color: .red,
            head: "You LOSE if…",
            body: contract.side == .call
                ? "\(movie.title) opens **at or below $\(Int(contract.strikeMillions))M**. The contract expires worthless and you lose the full \(totalCost, specifier: "%.2f") RC premium."
                : "\(movie.title) opens **at or above $\(Int(contract.strikeMillions))M**. The contract expires worthless and you lose the full \(totalCost, specifier: "%.2f") RC premium.",
            highlight: "Max loss is the premium — nothing more, no matter how far it misses."
        )
    }

    private var rewardLine: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(.orange).font(.caption)
            Text("Winning grants XP toward your next tier, and if you share the call publicly and it hits, followers.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func outcomeRow(icon: String, color: Color, head: String,
                            body text: String, highlight: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.body)
            VStack(alignment: .leading, spacing: 3) {
                Text(head).font(.caption.weight(.heavy)).foregroundStyle(color)
                Text(.init(text)).font(.caption)
                Text(highlight).font(.caption2).italic().foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - First-time tutorial

/// Full-screen walkthrough shown the FIRST time a user opens the
/// TradeSheet for a Call (or a Put). After they confirm they've read
/// it, an @AppStorage flag prevents it from firing again for that side.
struct FirstTradeTutorial: View {
    let side: ContractSide
    @Binding var dismissed: Bool

    var color: Color { side == .call ? .green : .red }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    section(
                        title: "1. You pay a premium up front.",
                        body: "The premium is what each contract costs. Multiply by your quantity — that's your total cost, and also the maximum you can lose. Nothing more, no matter what happens."
                    )
                    section(
                        title: side == .call
                            ? "2. If the movie opens ABOVE your strike, you get paid."
                            : "2. If the movie opens BELOW your strike, you get paid.",
                        body: side == .call
                            ? "Payoff per contract is max(actual − strike, 0) × multiplier. Every $1M above your strike pays you the multiplier (1 RC by default). Multiply by quantity."
                            : "Payoff per contract is max(strike − actual, 0) × multiplier. Every $1M below your strike pays you the multiplier (1 RC by default). Multiply by quantity."
                    )
                    section(
                        title: side == .call
                            ? "3. If the movie opens AT OR BELOW your strike, you lose the premium."
                            : "3. If the movie opens AT OR ABOVE your strike, you lose the premium.",
                        body: "The contract expires worthless. You lose exactly what you paid. Reel Coins refill every Monday, so it's never permanent."
                    )
                    PayoffChart(side: side,
                                strike: side == .call ? 100 : 40,
                                premium: side == .call ? 12 : 6,
                                multiplier: 1)
                        .padding(.top, 4)
                    Text("Green = profit. Red = loss. Orange dashed = strike. Blue dashed = break-even.")
                        .font(.caption2).foregroundStyle(.secondary)

                    Button {
                        dismissed = true
                    } label: {
                        Text("Got it — show me the trade").frame(maxWidth: .infinity).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(color)
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle(side == .call ? "About Calls" : "About Puts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismissed = true }
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: side == .call ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                    .foregroundStyle(color)
                    .font(.largeTitle)
                Text(side == .call ? "Calls are bullish bets." : "Puts are bearish bets.")
                    .font(.title2.bold())
            }
            Text(side == .call
                 ? "You're betting the movie will open BIGGER than the strike price you pick. The bigger it beats, the more you make."
                 : "You're betting the movie will open SMALLER than the strike price you pick. The bigger it misses, the more you make.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.bold))
            Text(body).font(.callout).foregroundStyle(.primary.opacity(0.9))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}
