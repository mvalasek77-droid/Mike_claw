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
                    }
                }
                Section {
                    Text("Season ends in 14 days. #1 is crowned Oracle of Summer 2026.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Leaderboard")
        }
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
