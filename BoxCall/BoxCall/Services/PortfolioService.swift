import Foundation
import Combine

@MainActor
final class PortfolioService: ObservableObject {
    static let shared = PortfolioService()

    @Published var user: User {
        didSet {
            if user.tier > oldValue.tier { RewardsService.shared.rankUp(to: user.tier) }
            persist()
        }
    }
    @Published private(set) var positions: [Position] = [] { didSet { persist() } }
    @Published private(set) var leaderboard: [LeaderboardEntry] = []

    private struct Saved: Codable {
        var user: User
        var positions: [Position]
    }

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("portfolio.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            self.user = saved.user
            self.positions = saved.positions
        } else {
            self.user = Self.freshUser()
        }
        // applyWeeklyCycle() runs from app launch, not here: it refunds limit
        // orders through OrderBookService, which calls back into `shared`.
        seedLeaderboard()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Saved(user: user, positions: positions)) else { return }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory,
                                                 withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Wipes every saved trade and returns the account to a brand-new state.
    func eraseAllData() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        positions = []
        user = Self.freshUser()
        seedLeaderboard()
    }

    private static func freshUser() -> User {
        // Every account starts identical. Paid tiers layer bonuses on top.
        User(
            handle: "you",
            reelCoins: StartingGrant.reelCoins,
            lifetimePnL: 0,
            weeklyAllowance: Membership.free.weeklyAllowance,
            lastAllowanceAt: RefillClock.lastMonday(),
            weeklyStake: StartingGrant.reelCoins,
            lastResetAt: RefillClock.lastSunday(),
            currentStreakWeeks: 0,
            longestStreakWeeks: 0,
            followingHandles: [],
            badges: [],
            trophies: [],
            bio: "Long the mid-budget original. Short the fifth sequel.",
            membership: .free,
            appleUserId: nil
        )
    }

    // MARK: - Membership

    /// Called by StoreService on purchase, restore, or a renewal update.
    func activateMembership(_ new: Membership, isNewPurchase: Bool = false) {
        let previous = user.membership
        mutateUser { u in
            u.membership = new
            u.weeklyAllowance = new.weeklyAllowance
        }
        // Exclusive icons go with Mogul, including on a move to a cheaper plan.
        if !new.hasAlternateIcons { Task { await AppIconChoice.classic.apply() } }
        if isNewPurchase, new.isPaid, new != previous {
            RewardsService.shared.celebrate("Welcome to \(new.displayName)",
                                            subtitle: "Your badge and tools are live",
                                            emoji: "🎟️")
            AnalyticsService.shared.track(.membershipPurchased(tier: new.rawValue))
        }
    }

    /// Called if a subscription lapses / is cancelled.
    func downgradeToFree() {
        mutateUser { u in
            u.membership = .free
            u.weeklyAllowance = Membership.free.weeklyAllowance
        }
        // Exclusive icons go with the membership.
        Task { await AppIconChoice.classic.apply() }
    }

    // MARK: - Trading

    enum TradeError: LocalizedError {
        case insufficientFunds, notFound, alreadySettled
        var errorDescription: String? {
            switch self {
            case .insufficientFunds:
                return "Not enough Reel Coins to cover the premium. Reduce the quantity or wait for Monday's fresh stake."
            case .notFound:
                return "That contract vanished."
            case .alreadySettled:
                return "Trading on this movie locked when it opened. It settles on the opening weekend number, usually reported Sunday."
            }
        }
    }

    /// Returns the new position id so the caller can attach a social post.
    @discardableResult
    func buy(contract: Contract, quantity: Int) throws -> UUID {
        guard let movie = MarketService.shared.movie(id: contract.movieId) else {
            throw TradeError.notFound
        }
        guard movie.isTradingOpen else { throw TradeError.alreadySettled }
        let cost = contract.premium * Double(quantity)
        guard user.reelCoins >= cost else { throw TradeError.insufficientFunds }

        mutateUser { $0.reelCoins -= cost }
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
            actualOWMillions: nil,
            movieTitle: movie.title,
            posterEmoji: movie.posterEmoji,
            genre: movie.genre
        ))
        MarketService.shared.recordBuy(contractId: contract.id, quantity: quantity)
        Haptics.trade()
        // If the movie opens in the next 24h, kick off a Live Activity.
        // Use the id we just captured — `positions.last` is only correct
        // when nothing else appended concurrently.
        if let m = MarketService.shared.movie(id: contract.movieId),
           m.releaseDate.timeIntervalSinceNow < 24 * 3600,
           let placed = positions.first(where: { $0.id == pid }) {
            LiveActivityService.start(movie: m, position: placed)
        }
        AnalyticsService.shared.track(.tradePlaced(
            movieId: contract.movieId, side: contract.side.rawValue,
            strike: contract.strikeMillions, qty: quantity, cost: cost))
        if user.badges.first(where: { $0.id == "first_call" }) == nil,
           let badge = Badge.make("first_call") {
            RewardsService.shared.award(badge: badge)
        }
        return pid
    }

    func closeAtMark(position: Position) {
        guard position.isOpen,
              MarketService.shared.movie(id: position.movieId)?.isTradingOpen ?? false else { return }
        let chain = MarketService.shared.chain(for: position.movieId)
        let fallback = chain.first { $0.id == position.contractId }?.premium
            ?? position.entryPremium
        let bid = MarketService.shared.quote(contractId: position.contractId)?.bid ?? fallback
        let proceeds = bid * Double(position.quantity)
        let credited = creditAfterStakeRepayment(proceeds, from: position)
        mutateUser { u in
            u.reelCoins += credited
            u.lifetimePnL += proceeds - position.cost
        }
        MarketService.shared.recordSell(contractId: position.contractId, quantity: position.quantity)
        Haptics.closeTrade()
        AnalyticsService.shared.track(.tradeClosed(
            movieId: position.movieId, pnl: proceeds - position.cost))
        if let idx = positions.firstIndex(where: { $0.id == position.id }) {
            positions[idx].settledPayout = proceeds
        }
    }

    // MARK: - Settlement

    func settle(movieId: String, actualMillions: Double) {
        var toSettle = positions.filter { $0.movieId == movieId && $0.isOpen }
        var wonAny = false
        var lostAny = false

        let movie = MarketService.shared.movie(id: movieId)

        for i in toSettle.indices {
            let p = toSettle[i]
            let intrinsic = p.side == .call
                ? max(actualMillions - p.strikeMillions, 0)
                : max(p.strikeMillions - actualMillions, 0)
            let payoutPerContract = intrinsic * p.multiplier
            let payout = payoutPerContract * Double(p.quantity)
            let net = payout - p.cost
            let credited = creditAfterStakeRepayment(payout, from: p)
            mutateUser { u in
                u.reelCoins += credited
                u.lifetimePnL += net
            }
            toSettle[i].settledPayout = payout
            toSettle[i].actualOWMillions = actualMillions

            if net > 0 {
                wonAny = true
                Haptics.won(large: net > 100)
                RewardsService.shared.recordWin(position: p, actual: actualMillions, netProfit: net)
            } else if net < 0 {
                lostAny = true
                Haptics.lost()
                RewardsService.shared.recordLoss(position: p)
            }
            SocialService.shared.attachOutcome(
                positionId: p.id,
                actual: actualMillions,
                payoutPerContract: payoutPerContract,
                netProfit: net
            )

            if let movie {
                NotificationsService.shared.notifySettlement(
                    movie: movie, position: toSettle[i],
                    actual: actualMillions, net: net)
            }
        }

        positions = positions.map { existing in
            if let updated = toSettle.first(where: { $0.id == existing.id }) { return updated }
            return existing
        }

        // A streak counts weeks, not movies: bump at most once per Monday cycle.
        let thisWeek = RefillClock.lastMonday()
        let alreadyBumped = (user.lastStreakBumpAt ?? .distantPast) >= thisWeek
        if wonAny && !lostAny && !alreadyBumped {
            RewardsService.shared.bumpWeeklyStreak()
            mutateUser { $0.lastStreakBumpAt = thisWeek }
        } else if lostAny && !wonAny && !alreadyBumped {
            RewardsService.shared.resetStreak()
        }

        if user.reelCoins < 1 {
            NotificationsService.shared.notifyOutOfCoins()
        }
    }

    /// A film that turns out to have opened already (a limited release
    /// going wide) had no fair market: every open trade on it is refunded
    /// at cost, with no profit or loss. Returns the amount refunded.
    @discardableResult
    func voidMarket(movieId: String) -> Double {
        var refunded = 0.0
        var updated = positions
        for i in updated.indices where updated[i].movieId == movieId && updated[i].isOpen {
            let p = updated[i]
            let credited = creditAfterStakeRepayment(p.cost, from: p)
            mutateUser { $0.reelCoins += credited }
            refunded += p.cost
            updated[i].settledPayout = p.cost
            updated[i].voided = true
        }
        positions = updated
        return refunded
    }

    // MARK: - Weekly allowance

    /// Sunday: the week's stake is taken back and profit stays.
    /// Monday: a fresh stake lands. Open positions are never touched, so
    /// trades on movies that haven't opened keep running through the reset.
    /// Safe to call any time — each step fires at most once per week.
    func applyWeeklyCycle(now: Date = Date()) {
        let sunday = RefillClock.lastSunday(before: now)
        if let lastReset = user.lastResetAt {
            if lastReset < sunday {
                // Resting orders aren't trades yet: refund them so their coins count as cash.
                OrderBookService.shared.cancelAll()
                let openCost = positions.filter(\.isOpen).reduce(0) { $0 + $1.cost }
                let result = WeeklyReset.reset(
                    cash: user.reelCoins,
                    openCost: openCost,
                    owed: user.stakeOwed ?? 0,
                    stake: user.weeklyStake ?? user.membership.weeklyAllowance)
                mutateUser { u in
                    u.reelCoins = result.cash
                    u.stakeOwed = result.owed
                    u.weeklyStake = 0
                    // The moment it ran, not the boundary: every trade open right
                    // now counted toward the reset, so every one must repay it.
                    u.lastResetAt = now
                }
            }
        } else {
            // Saved before the reset existed: start the cycle without a retroactive reset.
            mutateUser { $0.lastResetAt = sunday }
        }

        let monday = RefillClock.lastMonday(before: now)
        if user.lastAllowanceAt < monday {
            let allowance = user.membership.weeklyAllowance
            let grant = WeeklyReset.mondayGrant(allowance: allowance,
                                                stakeStillHeld: user.weeklyStake ?? 0)
            mutateUser { u in
                u.reelCoins += grant
                u.weeklyStake = allowance
                u.lastAllowanceAt = monday
            }
        }

        refreshLeaderboard(now: now)
        checkSeasonRollover(now: now)
    }

    /// A trade that was running at the last Sunday reset pays back the
    /// stake it was holding before its winnings hit the balance.
    private func creditAfterStakeRepayment(_ proceeds: Double, from position: Position) -> Double {
        guard let owed = user.stakeOwed, owed > 0,
              let reset = user.lastResetAt, position.openedAt < reset else { return proceeds }
        let result = WeeklyReset.settleCarried(proceeds: proceeds, cost: position.cost, owed: owed)
        mutateUser { $0.stakeOwed = result.owed }
        return result.credited
    }

    // MARK: - Social hooks used by RewardsService

    func mutateUser(_ transform: (inout User) -> Void) {
        var u = user
        transform(&u)
        // Rank follows the best total profit ever reached.
        if u.lifetimePnL > (u.bestProfit ?? 0) { u.bestProfit = u.lifetimePnL }
        user = u
    }

    /// Used by OrderBookService to spawn a position from a filled
    /// limit order without re-charging the user.
    func appendPosition(_ p: Position) {
        positions.append(p)
    }

    // MARK: - Leaderboard

    private func seedLeaderboard() {
        refreshLeaderboard()
    }

    /// Ranked by total trading profit (`lifetimePnL`). The weekly reset
    /// and subscription bonuses never move it, so the top
    /// spot — and the homepage review spotlight — can only be won by trading.
    func refreshLeaderboard(now: Date = Date()) {
        let settled = positions.filter { !$0.isOpen && $0.voided != true }
        let wins = settled.filter { ($0.settledPayout ?? 0) > $0.cost }.count
        let rate = settled.isEmpty ? 0 : Double(wins) / Double(settled.count)
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let weekly = settled
            .filter { $0.openedAt >= weekAgo }
            .reduce(0.0) { $0 + ($1.settledPayout ?? 0) - $1.cost }

        var entries = RivalLeague.rivals.map { r -> LeaderboardEntry in
            let profit = RivalLeague.profit(r, at: now)
            return LeaderboardEntry(id: "rival:\(r.handle)", handle: r.handle,
                             tier: Tier.forProfit(profit),
                             profit: profit,
                             weeklyPnL: RivalLeague.lastWeekPnL(r, at: now),
                             winRate: r.winRate, isCurrentUser: false)
        }
        entries.append(.init(id: "me", handle: user.handle, tier: user.tier,
                             profit: user.lifetimePnL, weeklyPnL: weekly,
                             winRate: rate, isCurrentUser: true))
        entries.sort { $0.profit > $1.profit }
        leaderboard = entries
    }

    var myRank: Int? {
        leaderboard.firstIndex(where: \.isCurrentUser).map { $0 + 1 }
    }

    /// At a season rollover, the trader who is #1 by total profit takes
    /// the previous season's Oracle title.
    private func checkSeasonRollover(now: Date) {
        let current = Season.name(at: now)
        guard let previous = user.lastSeasonChecked else {
            mutateUser { $0.lastSeasonChecked = current }
            return
        }
        guard previous != current else { return }
        if myRank == 1 { RewardsService.shared.crownSeasonOracle(seasonName: previous) }
        mutateUser { $0.lastSeasonChecked = current }
    }
}
