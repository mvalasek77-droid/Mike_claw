import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject var portfolio: PortfolioService

    var body: some View {
        NavigationStack {
            List {
                Section("This season") {
                    ForEach(Array(portfolio.leaderboard.enumerated()), id: \.element.id) { idx, entry in
                        HStack {
                            Text(rankGlyph(idx + 1))
                                .font(.title3)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("@\(entry.handle)")
                                        .fontWeight(entry.isCurrentUser ? .bold : .regular)
                                        .foregroundStyle(entry.tier >= .insider ? Color.yellow :
                                                         (entry.isCurrentUser ? .orange : .primary))
                                    if entry.tier >= .analyst {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(entry.tier.color)
                                            .font(.caption)
                                    }
                                }
                                HStack(spacing: 6) {
                                    Text(entry.tier.name)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(entry.tier.color)
                                    Text("· win rate \(Int(entry.winRate * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(entry.reelCoins, format: .number.precision(.fractionLength(0)))
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                                Text(entry.weeklyPnL, format: .number.precision(.fractionLength(0)).sign(strategy: .always()))
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(entry.weeklyPnL >= 0 ? .green : .red)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Rank \(idx + 1), \(entry.handle), \(entry.tier.name), \(Int(entry.reelCoins)) Reel Coins, win rate \(Int(entry.winRate * 100)) percent")
                    }
                }
                Section {
                    Text("Season ends \(seasonEndString). #1 is crowned Oracle of \(seasonName).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Leaderboard")
        }
    }

    private var seasonName: String {
        let cal = Calendar.current
        let month = cal.component(.month, from: Date())
        let year = cal.component(.year, from: Date())
        let name: String
        switch month {
        case 1...3:  name = "Winter"
        case 4...6:  name = "Spring"
        case 7...9:  name = "Summer"
        default:     name = "Fall"
        }
        return "\(name) \(year)"
    }

    private var seasonEndString: String {
        let cal = Calendar.current
        let month = cal.component(.month, from: Date())
        let endMonth: Int
        switch month {
        case 1...3:  endMonth = 4
        case 4...6:  endMonth = 7
        case 7...9:  endMonth = 10
        default:     endMonth = 1
        }
        let year = cal.component(.year, from: Date()) + (endMonth == 1 ? 1 : 0)
        guard let end = cal.date(from: DateComponents(year: year, month: endMonth, day: 1)) else {
            return "soon"
        }
        let days = cal.dateComponents([.day], from: Date(), to: end).day ?? 0
        if days <= 0 { return "soon" }
        return "in \(days) days"
    }

    private func rankGlyph(_ n: Int) -> String {
        switch n {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "\(n)"
        }
    }
}
