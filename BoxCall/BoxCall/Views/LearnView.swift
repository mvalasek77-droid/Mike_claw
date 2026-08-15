import SwiftUI

struct LearnView: View {
    var initialSection: LearnSection = .theBigIdea

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(LearnSection.allCases) { section in
                        section.view
                            .id(section)
                            .padding(.horizontal)
                    }
                    disclaimerFooter
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                }
                .padding(.top, 12)
            }
            .navigationTitle("How BoxCall Works")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if initialSection != .theBigIdea {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation { proxy.scrollTo(initialSection, anchor: .top) }
                    }
                }
            }
        }
    }

    private var disclaimerFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("BoxCall is entertainment. Reel Coins are play-money — they cannot be purchased, redeemed, or exchanged for anything of value. Nothing on this app is a securities offering, an event contract, or a wager.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sections

enum LearnSection: String, CaseIterable, Identifiable {
    case theBigIdea, whatsACall, whatsAPut, strike, premium, liveMarket, settlement, losingCoins, closeEarly, multiplier, rewards, glossary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .theBigIdea:   return "The big idea"
        case .whatsACall:   return "Calls: betting the movie opens BIG"
        case .whatsAPut:    return "Puts: betting the movie flops"
        case .strike:       return "The strike price"
        case .premium:      return "Premium & implied volatility"
        case .liveMarket:   return "The live market — how mark moves 24/7"
        case .settlement:   return "Opening weekend & settlement"
        case .losingCoins:  return "Losing coins — what actually happens"
        case .closeEarly:   return "Closing early at the mark"
        case .multiplier:   return "Multiplier"
        case .rewards:      return "What you win"
        case .glossary:     return "Glossary"
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .theBigIdea:   TheBigIdeaSection()
        case .whatsACall:   CallSection()
        case .whatsAPut:    PutSection()
        case .strike:       StrikeSection()
        case .premium:      PremiumSection()
        case .liveMarket:   LiveMarketSection()
        case .settlement:   SettlementSection()
        case .losingCoins:  LosingCoinsSection()
        case .closeEarly:   CloseEarlySection()
        case .multiplier:   MultiplierSection()
        case .rewards:      RewardsSection()
        case .glossary:     GlossarySection()
        }
    }
}

// MARK: - Building blocks

struct LearnHeader: View {
    let index: Int
    let title: String
    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
                .padding(6)
                .background(Circle().fill(.orange.opacity(0.15)))
            Text(title).font(.title3.bold())
        }
    }
}

struct LearnParagraph: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.primary.opacity(0.9))
    }
}

struct FormulaBox: View {
    let title: String
    let formula: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(formula)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .foregroundStyle(.orange)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground)))
    }
}

struct WorkedExample: View {
    let title: String
    let lines: [(String, String)]
    let verdict: String
    let verdictPositive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            VStack(spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, pair in
                    HStack {
                        Text(pair.0).foregroundStyle(.secondary)
                        Spacer()
                        Text(pair.1).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
            HStack {
                Image(systemName: verdictPositive ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(verdictPositive ? .green : .red)
                Text(verdict).font(.caption.weight(.semibold))
                    .foregroundStyle(verdictPositive ? .green : .red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Individual sections

struct TheBigIdeaSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 1, title: LearnSection.theBigIdea.title)
            LearnParagraph("Every big movie opens on a Friday and the studio reports a domestic three-day box-office number Monday morning. BoxCall lets you take a position on that number, in play-money Reel Coins.")
            LearnParagraph("Each movie has an options chain with strikes above and below the current consensus estimate. You pick a strike and either go Call (bullish — you think it opens higher) or Put (bearish — you think it opens lower). Your payoff scales with how right you are.")
            HStack(spacing: 10) {
                bullet("🟢", "Call = bullish", "You get paid when the movie opens above your strike.")
                bullet("🔴", "Put = bearish",  "You get paid when the movie opens below your strike.")
            }
            .padding(.top, 4)
        }
    }

    private func bullet(_ emoji: String, _ head: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) { Text(emoji); Text(head).font(.subheadline.weight(.bold)) }
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

struct CallSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 2, title: LearnSection.whatsACall.title)
            LearnParagraph("A Call is a bullish bet. You pay a premium up front, and in exchange you get paid the amount the movie opens above your strike — nothing if it opens at or below the strike.")
            FormulaBox(title: "Payoff per Call contract",
                       formula: "max(actual − strike, 0) × multiplier")
            PayoffChart(side: .call, strike: 100, premium: 12, multiplier: 1)
                .padding(.top, 4)
            Text("Green area = profit. Red area = loss. Orange dashed line is your strike. Blue dashed line is your break-even.")
                .font(.caption2).foregroundStyle(.secondary)
            WorkedExample(
                title: "Example — Neon Requiem (consensus $12M)",
                lines: [
                    ("You buy",         "10 Calls at $12M strike"),
                    ("Premium (each)",  "2.80 RC"),
                    ("Total cost",      "28 RC"),
                    ("Break-even",      "$14.8M opening"),
                    ("If it opens at $18M", "payoff = (18−12) × 1 × 10 = 60 RC"),
                    ("Net profit",      "+32 RC"),
                    ("If it opens at $10M", "payoff = 0 (strike not hit)"),
                    ("Net loss",        "-28 RC (premium)")
                ],
                verdict: "Max loss is capped at the premium you paid. Upside is uncapped.",
                verdictPositive: true
            )
        }
    }
}

struct PutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 3, title: LearnSection.whatsAPut.title)
            LearnParagraph("A Put is a bearish bet. You pay a premium up front, and in exchange you get paid the amount the movie opens below your strike — nothing if it opens at or above.")
            FormulaBox(title: "Payoff per Put contract",
                       formula: "max(strike − actual, 0) × multiplier")
            PayoffChart(side: .put, strike: 40, premium: 6, multiplier: 1)
                .padding(.top, 4)
            WorkedExample(
                title: "Example — Prowl (consensus $21M)",
                lines: [
                    ("You buy",         "5 Puts at $18M strike"),
                    ("Premium (each)",  "3.40 RC"),
                    ("Total cost",      "17 RC"),
                    ("Break-even",      "$14.6M opening"),
                    ("If it opens at $9M",  "payoff = (18−9) × 1 × 5 = 45 RC"),
                    ("Net profit",      "+28 RC"),
                    ("If it opens at $22M", "payoff = 0 (opened above strike)"),
                    ("Net loss",        "-17 RC (premium)")
                ],
                verdict: "Bomb Callers get paid. Max loss is your premium.",
                verdictPositive: true
            )
        }
    }
}

struct StrikeSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 4, title: LearnSection.strike.title)
            LearnParagraph("The strike is the dividing line between profit and loss. Every movie's chain has ten strikes — five above and five below the current consensus opening.")
            LearnParagraph("Picking the strike IS the game. Two things move in opposite directions:")
            HStack(alignment: .top, spacing: 10) {
                Column(head: "Deep ITM strike",
                       body: "For a Call: strike well below consensus. Almost certain to pay something → high premium, small edge, low upside multiple.")
                Column(head: "Deep OTM strike",
                       body: "For a Call: strike well above consensus. Only pays if the movie blows out → cheap premium, huge multiple if you're right.")
            }
            LearnParagraph("Contrarian traders — those who pick strikes far from consensus and hit — earn the Contrarian badge and outsized follower gains.")
        }
    }

    private func Column(head: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(head).font(.subheadline.weight(.bold))
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

struct PremiumSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 5, title: LearnSection.premium.title)
            LearnParagraph("The premium is the cost per contract — what you pay up front. Three things drive it:")
            bullet("Intrinsic value", "The payoff the contract would produce if the movie opened at today's consensus. In-the-money strikes are more expensive.")
            bullet("Time to expiry (DTE)", "The further out the release date, the more time for things to change — so options cost more. Premiums decay as the release approaches (real options traders call this theta).")
            bullet("Implied volatility (IV)", "How wide the range of plausible outcomes is. A $6M A24 indie has 70% IV because it could triple or bomb. A Marvel sequel has 22% IV — the outcome is more predictable. High IV = more expensive premiums on both Call AND Put.")
            FormulaBox(title: "Rough pricing model used in the mock chain",
                       formula: "premium ≈ intrinsic + consensus × IV × √(DTE/30) × exp(-|moneyness| × 1.8) × 0.5")
            LearnParagraph("In a live version, premiums come from an order book — the marginal buyer sets the price, and it moves in real time as tracking updates, reviews land, and presales roll in.")
        }
    }

    private func bullet(_ head: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkle").foregroundStyle(.orange).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(head).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct LiveMarketSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 6, title: LearnSection.liveMarket.title)
            LearnParagraph("Premiums are not static. Every contract's mark moves continuously — 24/7, whether you have the app open or not — as buys and sells push it around and news events shock a movie's whole chain.")
            FormulaBox(title: "Live pricing model",
                       formula: "mark = base × exp(demand / liquidity) × movieSentiment × (1 + noise)")
            bullet("Buys push the mark up.",
                   "Every contract you buy adds to the demand imbalance for that strike. The next tick, the mark reprices higher. Slippage is small when demand is small, larger when the whole crowd piles into one strike.")
            bullet("Sells push the mark down.",
                   "Closing a position at the mark removes demand and drops the price for the next buyer.")
            bullet("News moves the whole chain.",
                   "A bullish event (great reviews, presales spike, viral trailer) lifts the movie's sentiment multiplier — every Call mark goes up, every Put mark goes down. Bearish news does the reverse. Events land in the news ticker on each movie page.")
            bullet("Background NPC activity keeps the tape moving.",
                   "Even when no human is trading a strike, small bot orders drift the mark so the sparkline always has a story. In a live version, these are replaced by real user orders and market-maker liquidity.")
            LearnParagraph("The takeaway: entering early — when consensus is stable and news hasn't broken — usually gets you a better fill than piling in after the crowd. And you can trade the news itself: buy the dip on an overreaction, take profit into a spike.")
        }
    }

    private func bullet(_ head: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.orange).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(head).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SettlementSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 7, title: LearnSection.settlement.title)
            LearnParagraph("Trading on a movie closes when the first show goes up on Friday night. Over the weekend, the studio reports Friday, Saturday, and Sunday grosses. Monday morning, BoxCall pulls the reported domestic three-day number and settles every open position on that movie.")
            LearnParagraph("Settlement pays the intrinsic value of each contract:")
            HStack(spacing: 10) {
                FormulaBox(title: "Call settle", formula: "max(actual − K, 0) × mult × qty")
                FormulaBox(title: "Put settle",  formula: "max(K − actual, 0) × mult × qty")
            }
            LearnParagraph("The Reel Coins land in your balance automatically. If your position was public on the feed, an outcome banner (\"Called it.\" / \"Missed.\") attaches to your post and drives follower gains.")
        }
    }
}

struct LosingCoinsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 8, title: LearnSection.losingCoins.title)
            LearnParagraph("BoxCall is a real market. You will lose trades. Here's exactly what that looks like — and why it isn't the end of the world.")
            HStack(spacing: 10) {
                lossBullet(icon: "arrow.down.right.circle.fill", head: "Max loss is the premium.",
                           body: "Every contract you buy has a fixed downside. If your Call finishes out-of-the-money (movie opens at or below the strike), you lose exactly what you paid — never more. Same for Puts.")
                lossBullet(icon: "clock.arrow.circlepath", head: "Mark can drop before settlement.",
                           body: "If a movie's news turns against you, the live mark on your contract drops. Your open P&L is red until either you close at the mark (locking a smaller loss) or the movie settles.")
            }
            HStack(spacing: 10) {
                lossBullet(icon: "gift.fill", head: "You never go negative.",
                           body: "Reel Coins can't go below zero. Once you've spent your balance, trading pauses until your weekly refill lands.")
                lossBullet(icon: "arrow.clockwise.circle.fill", head: "Weekly refill is automatic.",
                           body: "Every account gets 500 RC free every week — forever. Even if you lose your last coin, you're back in the market next Monday. Subscribers refill faster (see Membership).")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("This is not real money.")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
                Text("Reel Coins are play-money. They can't be bought as balance (only via subscription bonuses), can't be redeemed for cash, and can't be transferred. Losing them costs nothing but time and pride. Winning them earns you status.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.10)))
        }
    }

    private func lossBullet(icon: String, head: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(.red)
            Text(head).font(.subheadline.weight(.bold))
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

struct CloseEarlySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 9, title: LearnSection.closeEarly.title)
            LearnParagraph("You don't have to hold until settlement. Every open position has a Close button that sells at the current mark price.")
            bullet("Take profit early", "If tracking spikes and your Call's mark doubles, you can lock in the gain without waiting for opening weekend to actually deliver.")
            bullet("Cut losses",         "If the movie's buzz collapses (bad reviews, marketing disaster) and your position is underwater, close early rather than eating the full premium.")
            bullet("Free up Reel Coins", "Closing releases the coins you tied up, so you can redeploy into a hotter market.")
            LearnParagraph("The mark drifts through the week — think of it as the live crowd-forecast for the movie's opening.")
        }
    }

    private func bullet(_ head: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrowshape.right.fill").foregroundStyle(.orange).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(head).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct MultiplierSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 10, title: LearnSection.multiplier.title)
            LearnParagraph("Every contract has a multiplier — the number of Reel Coins each dollar of intrinsic value converts to.")
            FormulaBox(title: "Default multiplier",
                       formula: "1 RC per $1M of intrinsic value")
            LearnParagraph("A Call at strike $12M that settles at $18M produces $6M intrinsic × 1 = 6 RC per contract. Multiply by your quantity. Future \"boosted\" markets (e.g. season finales) may run at 2× or 3× to spice up rare high-visibility releases.")
        }
    }
}

struct RewardsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 11, title: LearnSection.rewards.title)
            LearnParagraph("Reel Coins are the fuel — 500 refill weekly, and you never buy or redeem them. What actually accrues is status.")
            HStack(alignment: .top, spacing: 10) {
                pillar("🎯", "XP & tiers", "Wins grant XP proportional to profit. Six tiers unlock functional social power — verified checkmark, gold username, ability to create custom markets, pinned posts.")
                pillar("🏅", "Badges", "Feats trigger badges: Sniper (5 in a row), Bomb Caller (put that hits by 30%+), Rocket (call that beats by 40%+), Contrarian (win far from consensus).")
            }
            HStack(alignment: .top, spacing: 10) {
                pillar("👥", "Followers", "Winning public calls bring 3–12 new followers each. Reach compounds.")
                pillar("🏆", "Season titles", "Finish #1 for a season and earn a permanent \"Oracle · Summer 2026\" title on your trophy shelf.")
            }
        }
    }

    private func pillar(_ e: String, _ head: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) { Text(e); Text(head).font(.subheadline.weight(.bold)) }
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

struct GlossarySection: View {
    private let terms: [(String, String)] = [
        ("Strike",           "The opening-weekend number at which a contract flips from paying nothing to paying intrinsic value."),
        ("Premium",          "The price you pay per contract."),
        ("Intrinsic value",  "For a Call: actual − strike (or 0). For a Put: strike − actual (or 0). What the contract is worth at settlement."),
        ("Time value",       "The part of the premium beyond intrinsic — pays for optionality. Decays as opening day approaches."),
        ("IV (Implied Vol)", "How wide the plausible range of outcomes is. Higher IV → higher premiums."),
        ("DTE",              "Days to expiry — days until the movie opens."),
        ("Mark",             "The current mid-price for a contract. What you'd get if you closed right now."),
        ("Open interest",    "How many contracts are outstanding across all players. Popularity signal."),
        ("Moneyness",        "How far your strike is from consensus. ITM = in-the-money (already profitable). OTM = out-of-the-money (needs movement)."),
        ("Consensus",        "The current crowd/tracker estimate of opening weekend. The chain is built around it."),
        ("Multiplier",       "Reel Coins per $1M of intrinsic value per contract (default: 1)."),
        ("Settlement",       "The Monday process that pays intrinsic value on every open position based on the reported opening-weekend gross.")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LearnHeader(index: 12, title: LearnSection.glossary.title)
            ForEach(terms, id: \.0) { term in
                VStack(alignment: .leading, spacing: 2) {
                    Text(term.0).font(.subheadline.weight(.bold)).foregroundStyle(.orange)
                    Text(term.1).font(.caption)
                }
                .padding(.vertical, 2)
            }
        }
    }
}
