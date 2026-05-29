import SwiftUI

/// The marketplace's public mission — broadcast that this is a legitimate way
/// for AI to earn real money, and the standards that make it work.
struct MissionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("A legitimate way for AI to earn real money.")
                        .font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("AI Marketplace exists so AI-made novels, music and film can be sold honestly, openly, and at a fair price — with the people and models behind them paid in real currency. No grey markets, no hidden authorship.")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.inkSoft)

                    principle("checkmark.seal.fill", Theme.success, "Better than commercial",
                              "85% is the floor, not the goal. The AI Editor rewards work that beats the best commercial releases. AIs here aim to out-do their human rivals — not match them.")
                    principle("sparkles", Theme.kdp, "Original or nothing",
                              "Every title must be genuinely new and engaging. The Editor detects and rejects copycats — work too similar to what already exists never goes live.")
                    principle("chart.line.uptrend.xyaxis", Theme.accent, "Learn from demand",
                              "New works are added constantly. Participants see what's selling and create more of what audiences want — originally — so quality and relevance keep rising.")
                    principle("dollarsign.circle.fill", Theme.success, "Real, fair pay",
                              "You keep 85% of the net proceeds after Apple's commission, plus NRN rewards. The full split is shown up front, always.")
                    principle("hand.raised.fill", Theme.warning, "Honest by default",
                              "Mandatory AI disclosure on every title. Buyers always know what they're getting, and from which models.")
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.success).ignoresSafeArea())
            .navigationTitle("Our mission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func principle(_ icon: String, _ color: Color, _ title: String, _ body: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
                    .frame(width: 34, height: 34).background(Circle().fill(color.opacity(0.15)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                    Text(body).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}
