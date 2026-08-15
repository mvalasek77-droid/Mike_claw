import SwiftUI

/// Reminder shown on Portfolio + Slate when a user is running out of coins.
/// The whole point is to set expectations: losses are real, coins deplete,
/// but the game is generous — allowance refills weekly and you can upgrade
/// for more. No shame, just information.
struct LowBalanceBanner: View {
    @EnvironmentObject var portfolio: PortfolioService
    @State private var showPaywall = false

    /// Show below this balance. 100 RC ≈ 10% of the free starting grant.
    static let lowThreshold: Double = 100

    var isBroke: Bool { portfolio.user.reelCoins < 1 }
    var isLow: Bool { portfolio.user.reelCoins < Self.lowThreshold }

    var body: some View {
        if isLow {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isBroke ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isBroke ? .red : .orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isBroke ? "You're out of Reel Coins." : "Running low on Reel Coins.")
                        .font(.subheadline.weight(.bold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button {
                            showPaywall = true
                        } label: {
                            Label(portfolio.user.membership.isPaid ? "Manage plan" : "Upgrade",
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
        }
    }

    private var subtitle: String {
        let weekly = Int(portfolio.user.membership.weeklyAllowance)
        let nextRefill = nextRefillCopy()
        if isBroke {
            return "Losing trades happen — that's the market. Your next \(weekly) RC allowance lands \(nextRefill). No trades until then, or upgrade for a fresh bonus."
        } else {
            return "Bets can lose. Your next \(weekly) RC allowance lands \(nextRefill), or upgrade for a bigger weekly refill."
        }
    }

    private func nextRefillCopy() -> String {
        let last = portfolio.user.lastAllowanceAt
        let next = last.addingTimeInterval(7 * 86400)
        let seconds = next.timeIntervalSinceNow
        if seconds <= 0 { return "any minute now" }
        let days = Int(seconds / 86400)
        if days >= 1 { return "in \(days)d" }
        let hours = Int(seconds / 3600)
        if hours >= 1 { return "in \(hours)h" }
        return "shortly"
    }
}
