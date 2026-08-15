import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject var portfolio: PortfolioService

    var body: some View {
        NavigationStack {
            List {
                Section("This season") {
                    ForEach(Array(portfolio.leaderboard.enumerated()), id: \.element.id) { idx, entry in
                        HStack {
                            Text("\(idx + 1)")
                                .font(.caption.monospacedDigit())
                                .frame(width: 28)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text("@\(entry.handle)")
                                    .fontWeight(entry.isCurrentUser ? .bold : .regular)
                                    .foregroundStyle(entry.isCurrentUser ? .orange : .primary)
                                Text("win rate \(Int(entry.winRate * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
            }
            .navigationTitle("Leaderboard")
        }
    }
}
