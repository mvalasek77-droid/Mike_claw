import Foundation
import Combine

/// Badges, streaks, followers and rank-up moments. Everything here is
/// play-status earned by trading: no cash, no IAP.
@MainActor
final class RewardsService: ObservableObject {
    static let shared = RewardsService()

    @Published private(set) var lastToast: RewardToast?
    private var recentWinsInARow = 0

    struct RewardToast: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let subtitle: String
        let emoji: String
    }

    private init() {}

    // MARK: - Public API

    func celebrate(_ title: String, subtitle: String, emoji: String) {
        toast(title, subtitle: subtitle, emoji: emoji)
    }

    /// Called by PortfolioService whenever best total profit crosses a rank threshold.
    func rankUp(to tier: Tier) {
        toast("You're now a \(tier.name)", subtitle: tier.perks.first ?? "New rank unlocked", emoji: "⭐️")
        NotificationsService.shared.notifyTier(tier)
        AnalyticsService.shared.track(.tierPromoted(to: tier.name))
        Haptics.tierUp()
    }

    func award(badge: Badge) {
        var wasNew = false
        PortfolioService.shared.mutateUser { u in
            if !u.badges.contains(where: { $0.id == badge.id }) {
                u.badges.append(badge)
                wasNew = true
            }
        }
        if wasNew {
            toast("Badge unlocked", subtitle: "\(badge.name) — \(badge.blurb)", emoji: badge.emoji)
            NotificationsService.shared.notifyBadge(badge)
            AnalyticsService.shared.track(.badgeUnlocked(id: badge.id))
            Haptics.badge()
        }
    }

    func recordWin(position: Position, actual: Double, netProfit: Double) {
        let followersGained = Int.random(in: 3...12)
        PortfolioService.shared.mutateUser { $0.followerCount += followersGained }
        toast("+\(Int(netProfit)) RC profit", subtitle: "Winning \(position.side.display) settled — new followers", emoji: "🎯")
        NotificationsService.shared.notifyFollowers(gained: followersGained)

        recentWinsInARow += 1
        if recentWinsInARow == 5, let b = Badge.make("sniper") { award(badge: b) }

        // Feat-specific badges
        if let movie = MarketService.shared.movie(id: position.movieId) {
            let deltaFromConsensus = (actual - movie.consensusOpeningMillions) / max(1, movie.consensusOpeningMillions)
            if position.side == .put && deltaFromConsensus <= -0.3,
               let b = Badge.make("bomb_caller") { award(badge: b) }
            if position.side == .call && deltaFromConsensus >= 0.4,
               let b = Badge.make("rocket") { award(badge: b) }
            if abs(deltaFromConsensus) >= 0.2,
               let b = Badge.make("contrarian") { award(badge: b) }
        }

        // Traded 20 distinct movies?
        let distinctMovies = Set(PortfolioService.shared.positions.map { $0.movieId }).count
        if distinctMovies >= 20, let b = Badge.make("cinephile") { award(badge: b) }
    }

    func recordLoss(position: Position) {
        recentWinsInARow = 0
    }

    func bumpWeeklyStreak() {
        PortfolioService.shared.mutateUser { u in
            u.currentStreakWeeks += 1
            u.longestStreakWeeks = max(u.longestStreakWeeks, u.currentStreakWeeks)
        }
        let streak = PortfolioService.shared.user.currentStreakWeeks
        toast("🔥 \(streak)-week streak", subtitle: "Keep it going", emoji: "🔥")
        if streak == 3, let b = Badge.make("streak_3") { award(badge: b) }
        if streak == 10, let b = Badge.make("streak_10") { award(badge: b) }
    }

    func resetStreak() {
        PortfolioService.shared.mutateUser { $0.currentStreakWeeks = 0 }
    }

    /// Called at the end of a season by a server job (or manually via debug menu).
    func crownSeasonOracle(seasonName: String) {
        PortfolioService.shared.mutateUser { u in
            u.trophies.append("Oracle · \(seasonName)")
        }
        if let b = Badge.make("oracle_of") { award(badge: b) }
    }

    // MARK: - Toast helper

    private func toast(_ title: String, subtitle: String, emoji: String) {
        lastToast = RewardToast(title: title, subtitle: subtitle, emoji: emoji)
    }

    func dismissToast() { lastToast = nil }
}
