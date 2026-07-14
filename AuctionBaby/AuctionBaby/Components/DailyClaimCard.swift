import SwiftUI
import UIKit

/// The come-back-tomorrow hook: a once-a-day Gavel claim whose reward grows
/// with the streak (capped at 7×). Renders nothing once today is claimed.
struct DailyClaimCard: View {
    @EnvironmentObject private var store: AuctionStore
    @State private var pulse = false

    private var nextReward: Int {
        let streakWillContinue: Bool = {
            guard let last = store.lastDailyClaim else { return false }
            let cal = Calendar.current
            guard let nextDay = cal.date(byAdding: .day, value: 1, to: last) else { return false }
            return cal.isDate(nextDay, inSameDayAs: Date())
        }()
        let nextStreak = streakWillContinue ? store.dailyStreak + 1 : 1
        return AuctionStore.dailyGavelBase * min(nextStreak, 7)
    }

    var body: some View {
        VStack(spacing: 10) {
            if store.canClaimDaily() { claimRow }
            docketRow
        }
    }

    private var claimRow: some View {
        Button {
            store.claimDaily()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.goldGradient))
                    .scaleEffect(pulse ? 1.08 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nextReward > AuctionStore.dailyGavelBase ? "Daily streak ready"
                                                           : "Daily Gavels ready")
                        .font(.system(size: 14, weight: .heavy, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("Claim \(Tally.compact(nextReward)) Gavels — or a mystery bonus.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Text("CLAIM")
                    .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.goldGradient))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.cornerL).fill(Theme.gold.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerL)
                .strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel("Claim your daily \(nextReward) Gavels")
    }

    /// The Docket sidebar: shows streak-freeze inventory + a buy button when
    /// the user is on a streak worth protecting.
    @ViewBuilder private var docketRow: some View {
        if store.dailyStreak > 1 || store.streakFreezeCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: "snowflake").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.verify)
                if store.streakFreezeCount > 0 {
                    Text("\(store.streakFreezeCount)× streak-freeze — miss a day, streak survives.")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text("No streak-freeze. One miss and day \(store.dailyStreak) resets.")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Button {
                    store.buyStreakFreeze()
                } label: {
                    Text("+\(AuctionStore.streakFreezeGavelCost) ⚖︎")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.verify)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().stroke(Theme.verify.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Buy a streak-freeze for \(AuctionStore.streakFreezeGavelCost) Gavels")
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.04)))
        }
    }
}
