import SwiftUI

/// Reminder shown on Portfolio + Slate when a user is running out of coins.
/// Losses are real — coins deplete — but every account resets on Monday.
/// The banner surfaces the exact countdown and (if applicable) an
/// Upgrade CTA for users who don't want to wait.
struct LowBalanceBanner: View {
    @EnvironmentObject var portfolio: PortfolioService
    @State private var showPaywall = false
    @State private var ticker: Date = Date()

    /// Show below this balance. 100 RC ≈ 10% of the free starting grant.
    static let lowThreshold: Double = 100

    var isBroke: Bool { portfolio.user.reelCoins < 1 }
    var isLow: Bool { portfolio.user.reelCoins < Self.lowThreshold }

    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        if isLow {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isBroke ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isBroke ? .red : .orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(isBroke ? "You're out of Reel Coins." : "Running low on Reel Coins.")
                        .font(.subheadline.weight(.bold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    refillRow
                    if !portfolio.user.membership.isPaid || isBroke {
                        Button {
                            showPaywall = true
                        } label: {
                            Label(portfolio.user.membership.isPaid ? "Manage plan" : "Upgrade to skip the wait",
                                  systemImage: "star.circle")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill((isBroke ? Color.red : .orange).opacity(0.12)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke((isBroke ? Color.red : .orange).opacity(0.35), lineWidth: 1)
            )
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .onReceive(tick) { ticker = $0 }
        }
    }

    private var subtitle: String {
        if isBroke {
            return "Losing trades happen — that's the market. Trading pauses until your allowance lands. Every account resets every Monday."
        } else {
            return "Bets can lose the full premium. Every account resets every Monday with a fresh allowance."
        }
    }

    private var refillRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(.orange)
                .font(.caption)
            Text("Next refill: **Monday** · in \(RefillClock.countdownString(from: ticker))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary.opacity(0.9))
        }
        .padding(.top, 2)
    }
}
