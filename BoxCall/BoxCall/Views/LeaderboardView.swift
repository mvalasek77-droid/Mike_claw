import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject var portfolio: PortfolioService

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                                    if entry.tier == .legend {
                                        Image(systemName: "rosette")
                                            .foregroundStyle(Tier.legend.color)
                                            .font(.caption)
                                            .accessibilityLabel("Legend")
                                    }
                                    if entry.isCurrentUser { MemberFlair() } else { SimulatedTag() }
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
                                Text(entry.profit, format: .number.precision(.fractionLength(0)).sign(strategy: .always()))
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                                    .foregroundStyle(entry.profit >= 0 ? Color.primary : .red)
                                Text("\(entry.weeklyPnL >= 0 ? "+" : "")\(Int(entry.weeklyPnL)) this wk")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(entry.weeklyPnL >= 0 ? .green : .red)
                            }
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(idx < 5 ? Color.orange.opacity(0.06) : nil)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Rank \(idx + 1), \(entry.handle)\(entry.isCurrentUser ? "" : ", simulated trader"), \(entry.tier.name), total profit \(Int(entry.profit)) Reel Coins, win rate \(Int(entry.winRate * 100)) percent")
                    }
                } header: {
                    Text("Total profit")
                } footer: {
                    Text("Ranked by total trading profit — the weekly reset never touches it. Everyone marked SIM is part of BoxCall's simulated league: automated traders playing the same slate. Ranks from Analyst to Legend are earned the same way, and the top 5 get their latest review spotlighted on the Marquee home screen.")
                }
                Section {
                    Text("\(Season.name(at: Date())) ends \(seasonEndString). Whoever is #1 in total profit then is crowned its Oracle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Leaderboard")
            .onAppear { portfolio.refreshLeaderboard() }
        }
    }

    private var seasonEndString: String {
        guard let end = Season.end(after: Date()) else { return "soon" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
        return days <= 0 ? "soon" : "in \(days) days"
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
