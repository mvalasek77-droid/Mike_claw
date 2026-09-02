import SwiftUI

/// Monday-morning "here's what happened this weekend" card. Shows the
/// positions that settled since the last time the user saw a recap,
/// tallied, with the single biggest swing called out. Dismisses to
/// UserDefaults so it appears once per settlement wave.
struct WeekendRecap: View {
    @EnvironmentObject var portfolio: PortfolioService
    @EnvironmentObject var market: MarketService
    @AppStorage("recap.lastSeenSettledCount") private var lastSeen: Int = 0
    @State private var confettiTrigger = 0

    private var settled: [Position] { portfolio.positions.filter { !$0.isOpen } }
    private var fresh: [Position] { Array(settled.suffix(max(0, settled.count - lastSeen))) }

    private var net: Double {
        fresh.reduce(0) { $0 + (($1.settledPayout ?? 0) - $1.cost) }
    }
    private var wins: Int { fresh.filter { (($0.settledPayout ?? 0) - $0.cost) > 0 }.count }
    private var biggest: Position? {
        fresh.max { abs(($0.settledPayout ?? 0) - $0.cost) < abs(($1.settledPayout ?? 0) - $1.cost) }
    }

    var body: some View {
        if !fresh.isEmpty {
            ZStack {
                card
                ConfettiBurst(trigger: confettiTrigger)
            }
            .onAppear { if net > 0 { confettiTrigger += 1 } }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MarqueeBulbs(count: 10)
                Spacer()
                Button {
                    lastSeen = settled.count
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.cream.opacity(0.6))
                }
                .accessibilityLabel("Dismiss weekend recap")
            }
            Text("WEEKEND RECAP")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Theme.bulbGlow)
            Text(headline)
                .font(Theme.Type.marqueeH2)
                .foregroundStyle(Theme.cream)
            HStack(spacing: 16) {
                stat("Settled", "\(fresh.count)")
                stat("Won", "\(wins)")
                stat("Net", String(format: "%+.0f RC", net), color: net >= 0 ? Theme.bull : Theme.bear)
            }
            if let b = biggest, let m = market.movie(id: b.movieId) {
                let swing = (b.settledPayout ?? 0) - b.cost
                HStack(spacing: 10) {
                    Text(m.posterEmoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(swing >= 0 ? "Biggest win" : "Biggest miss")
                            .font(.caption2).foregroundStyle(Theme.cream.opacity(0.6))
                        Text("\(m.title) · \(b.side.plain) $\(Int(b.strikeMillions))M")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.cream)
                        if let actual = b.actualOWMillions {
                            Text("Opened at $\(actual, specifier: "%.1f")M")
                                .font(.caption2).foregroundStyle(Theme.cream.opacity(0.7))
                        }
                    }
                    Spacer()
                    Text(swing, format: .number.precision(.fractionLength(0)).sign(strategy: .always()))
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .foregroundStyle(swing >= 0 ? Theme.bull : Theme.bear)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(.black.opacity(0.35)))
            }
        }
        .padding(Theme.Space.lg)
        .background(
            LinearGradient(colors: [Theme.velvetRed, Theme.stageBlack],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Theme.marqueeGold.opacity(0.6), lineWidth: 1.5)
        )
    }

    private var headline: String {
        if net > 100 { return "You called it. 🎯" }
        if net > 0   { return "In the green." }
        if net == 0  { return "Flat weekend." }
        if net > -100 { return "Tough weekend. Monday's a fresh start." }
        return "Ouch. Coins reset Monday."
    }

    private func stat(_ label: String, _ value: String, color: Color = Theme.cream) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Theme.cream.opacity(0.6))
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
        }
    }
}
