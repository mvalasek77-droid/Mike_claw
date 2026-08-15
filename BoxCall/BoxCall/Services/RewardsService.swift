import Foundation
import Combine

/// Grants XP, badges, streaks, and followers when trades settle.
/// Everything here is play-status: no cash, no IAP.
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

    func grant(xp amount: Int, reason: String) {
        PortfolioService.shared.mutateUser { $0.xp += amount }
        toast("+\(amount) XP", subtitle: reason, emoji: "⚡️")
    }

    func award(badge: Badge) {
        PortfolioService.shared.mutateUser { u in
            if !u.badges.contains(where: { $0.id == badge.id }) {
                u.badges.append(badge)
            }
        }
        toast("Badge unlocked", subtitle: "\(badge.name) — \(badge.blurb)", emoji: badge.emoji)
    }

    func recordWin(position: Position, actual: Double, netProfit: Double) {
        // Base XP scaled by profit; magnitude bonus for calling something far from consensus.
        let baseXP = Int(min(500, max(25, netProfit)))
        PortfolioService.shared.mutateUser { u in
            u.xp += baseXP
            u.followerCount += Int.random(in: 3...12)   // your call went viral
        }
        toast("+\(baseXP) XP", subtitle: "Winning \(position.side.display) settled — new followers", emoji: "🎯")

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
        // A tiny XP grant so losing still feels like progress; you learned something.
        PortfolioService.shared.mutateUser { $0.xp += 5 }
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
