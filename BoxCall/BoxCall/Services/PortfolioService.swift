import Foundation
import Combine

final class PortfolioService: ObservableObject {
    static let shared = PortfolioService()

    @Published private(set) var user: User
    @Published private(set) var positions: [Position] = []
    @Published private(set) var leaderboard: [LeaderboardEntry] = []

    private init() {
        self.user = User(
            handle: "you",
            reelCoins: 1000,
            lifetimePnL: 0,
            weeklyAllowance: 500,
            lastAllowanceAt: Date().addingTimeInterval(-8 * 86400)
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

    func buy(contract: Contract, quantity: Int) throws {
        guard let movie = MarketService.shared.movie(id: contract.movieId) else {
            throw TradeError.notFound
        }
        guard !movie.isSettled else { throw TradeError.alreadySettled }
        let cost = contract.premium * Double(quantity)
        guard user.reelCoins >= cost else { throw TradeError.insufficientFunds }

        user.reelCoins -= cost
        positions.append(.init(
            id: UUID(),
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
    }

    /// Sell to close at current mark. Play-money — no fees.
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

    /// Called when opening weekend concludes for a movie. Pays intrinsic value.
    func settle(movieId: String, actualMillions: Double) {
        var toSettle = positions.filter { $0.movieId == movieId && $0.isOpen }
        for i in toSettle.indices {
            let p = toSettle[i]
            let intrinsic = p.side == .call
                ? max(actualMillions - p.strikeMillions, 0)
                : max(p.strikeMillions - actualMillions, 0)
            let payout = intrinsic * p.multiplier * Double(p.quantity)
            user.reelCoins += payout
            user.lifetimePnL += payout - p.cost
            toSettle[i].settledPayout = payout
            toSettle[i].actualOWMillions = actualMillions
        }
        // write settled ones back
        positions = positions.map { existing in
            if let updated = toSettle.first(where: { $0.id == existing.id }) { return updated }
            return existing
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

    // MARK: - Leaderboard mock

    private func seedLeaderboard() {
        let others: [(String, Double, Double, Double)] = [
            ("popcornshark", 8420, 1830, 0.62),
            ("indieyoda",    5210,  940, 0.58),
            ("openingnight", 3100,  410, 0.51),
            ("marqueemaven", 2745, -220, 0.47),
            ("greenlight",   1980,  120, 0.54),
            ("trailerbait",  1420, -310, 0.42)
        ]
        var entries = others.map { LeaderboardEntry(id: $0.0, handle: $0.0, reelCoins: $0.1, weeklyPnL: $0.2, winRate: $0.3, isCurrentUser: false) }
        entries.append(.init(id: user.handle, handle: user.handle, reelCoins: user.reelCoins, weeklyPnL: 0, winRate: 0, isCurrentUser: true))
        entries.sort { $0.reelCoins > $1.reelCoins }
        leaderboard = entries
    }

    func refreshLeaderboard() {
        leaderboard = leaderboard.map { entry in
            guard entry.isCurrentUser else { return entry }
            return .init(id: entry.id, handle: entry.handle,
                         reelCoins: user.reelCoins,
                         weeklyPnL: user.lifetimePnL,
                         winRate: entry.winRate,
                         isCurrentUser: true)
        }.sorted { $0.reelCoins > $1.reelCoins }
    }
}
