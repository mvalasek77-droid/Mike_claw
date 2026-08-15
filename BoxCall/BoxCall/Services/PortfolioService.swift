import Foundation
import Combine

final class PortfolioService: ObservableObject {
    static let shared = PortfolioService()

    @Published var user: User
    @Published private(set) var positions: [Position] = []
    @Published private(set) var leaderboard: [LeaderboardEntry] = []

    private init() {
        self.user = User(
            handle: "you",
            reelCoins: 1000,
            lifetimePnL: 0,
            weeklyAllowance: 500,
            lastAllowanceAt: Date().addingTimeInterval(-8 * 86400),
            xp: 0,
            currentStreakWeeks: 0,
            longestStreakWeeks: 0,
            followerCount: 0,
            followingHandles: [],
            badges: [],
            trophies: [],
            bio: "Long the mid-budget original. Short the fifth sequel."
        )
        seedLeaderboard()
        redeemWeeklyIfDue()
    }

    // MARK: - Trading

    enum TradeError: LocalizedError {
        case insufficientFunds, notFound, alreadySettled
        var errorDescription: String? {
            switch self {
            case .insufficientFunds: return "Not enough Reel Coins."
            case .notFound: return "That contract vanished."
            case .alreadySettled: return "Trading has closed on this movie."
            }
        }
    }

    /// Returns the new position id so the caller can attach a social post.
    @discardableResult
    func buy(contract: Contract, quantity: Int) throws -> UUID {
        guard let movie = MarketService.shared.movie(id: contract.movieId) else {
            throw TradeError.notFound
        }
        guard !movie.isSettled else { throw TradeError.alreadySettled }
        let cost = contract.premium * Double(quantity)
        guard user.reelCoins >= cost else { throw TradeError.insufficientFunds }

        user.reelCoins -= cost
        let pid = UUID()
        positions.append(.init(
            id: pid,
            contractId: contract.id,
            movieId: contract.movieId,
            side: contract.side,
            strikeMillions: contract.strikeMillions,
            multiplier: contract.multiplier,
            quantity: quantity,
            entryPremium: contract.premium,
            openedAt: Date(),
            settledPayout: nil,
            actualOWMillions: nil
        ))
        RewardsService.shared.grant(xp: 10, reason: "Placed a trade")
        if user.badges.first(where: { $0.id == "first_call" }) == nil,
           let badge = Badge.make("first_call") {
            RewardsService.shared.award(badge: badge)
        }
        return pid
    }

    func closeAtMark(position: Position) {
        guard position.isOpen else { return }
        let chain = MarketService.shared.chain(for: position.movieId)
        let mark = chain.first { $0.id == position.contractId }?.premium ?? position.entryPremium
        let proceeds = mark * Double(position.quantity)
        user.reelCoins += proceeds
        user.lifetimePnL += proceeds - position.cost
        positions.removeAll { $0.id == position.id }
    }

    // MARK: - Settlement

    func settle(movieId: String, actualMillions: Double) {
        var toSettle = positions.filter { $0.movieId == movieId && $0.isOpen }
        var wonAny = false
        var lostAny = false

        for i in toSettle.indices {
            let p = toSettle[i]
            let intrinsic = p.side == .call
                ? max(actualMillions - p.strikeMillions, 0)
                : max(p.strikeMillions - actualMillions, 0)
            let payoutPerContract = intrinsic * p.multiplier
            let payout = payoutPerContract * Double(p.quantity)
            let net = payout - p.cost
            user.reelCoins += payout
            user.lifetimePnL += net
            toSettle[i].settledPayout = payout
            toSettle[i].actualOWMillions = actualMillions

            if net > 0 {
                wonAny = true
                RewardsService.shared.recordWin(position: p, actual: actualMillions, netProfit: net)
                SocialService.shared.attachOutcome(
                    positionId: p.id,
                    actual: actualMillions,
                    payoutPerContract: payoutPerContract,
                    netProfit: net
                )
            } else {
                lostAny = true
                RewardsService.shared.recordLoss(position: p)
                SocialService.shared.attachOutcome(
                    positionId: p.id,
                    actual: actualMillions,
                    payoutPerContract: payoutPerContract,
                    netProfit: net
                )
            }
        }

        positions = positions.map { existing in
            if let updated = toSettle.first(where: { $0.id == existing.id }) { return updated }
            return existing
        }

        if wonAny && !lostAny {
            RewardsService.shared.bumpWeeklyStreak()
        } else if lostAny {
            RewardsService.shared.resetStreak()
        }
    }

    // MARK: - Weekly allowance

    func redeemWeeklyIfDue() {
        let week: TimeInterval = 7 * 86400
        if Date().timeIntervalSince(user.lastAllowanceAt) >= week {
            user.reelCoins += user.weeklyAllowance
            user.lastAllowanceAt = Date()
        }
    }

    // MARK: - Social hooks used by RewardsService

    func mutateUser(_ transform: (inout User) -> Void) {
        transform(&user)
    }

    // MARK: - Leaderboard mock

    private func seedLeaderboard() {
        let others: [(String, Tier, Double, Double, Double)] = [
            ("popcornshark",  .studioHead, 8420, 1830, 0.62),
            ("indieyoda",     .producer,   5210,  940, 0.58),
            ("openingnight",  .insider,    3100,  410, 0.51),
            ("marqueemaven",  .insider,    2745, -220, 0.47),
            ("greenlight",    .analyst,    1980,  120, 0.54),
            ("trailerbait",   .analyst,    1420, -310, 0.42)
        ]
        var entries = others.map {
            LeaderboardEntry(id: $0.0, handle: $0.0, tier: $0.1,
                             reelCoins: $0.2, weeklyPnL: $0.3, winRate: $0.4,
                             isCurrentUser: false)
        }
        entries.append(.init(id: user.handle, handle: user.handle, tier: user.tier,
                             reelCoins: user.reelCoins, weeklyPnL: 0,
                             winRate: 0, isCurrentUser: true))
        entries.sort { $0.reelCoins > $1.reelCoins }
        leaderboard = entries
    }

    func refreshLeaderboard() {
        leaderboard = leaderboard.map { entry in
            guard entry.isCurrentUser else { return entry }
            return .init(id: entry.id, handle: entry.handle, tier: user.tier,
                         reelCoins: user.reelCoins, weeklyPnL: user.lifetimePnL,
                         winRate: entry.winRate, isCurrentUser: true)
        }.sorted { $0.reelCoins > $1.reelCoins }
    }
}
