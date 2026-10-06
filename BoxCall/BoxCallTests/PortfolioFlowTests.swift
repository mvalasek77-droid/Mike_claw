import XCTest
@testable import BoxCall

/// Drives the real services end to end: buy, settle, sell, the weekly
/// reset, the profit leaderboard and account deletion. Each test starts
/// from a wiped account.
final class PortfolioFlowTests: XCTestCase {

    // MARK: - Trading

    @MainActor
    func testBuy_chargesThePremium_withoutTouchingProfit() throws {
        let portfolio = freshAccount()
        let contract = try tradableContract(.call)

        try portfolio.buy(contract: contract, quantity: 3)

        XCTAssertEqual(portfolio.user.reelCoins, 1_000 - contract.premium * 3, accuracy: 0.001)
        XCTAssertEqual(portfolio.positions.count, 1)
        XCTAssertEqual(portfolio.user.lifetimePnL, 0)
    }

    @MainActor
    func testBuy_moreThanYouHave_isRefused() throws {
        let portfolio = freshAccount()
        let contract = try tradableContract(.call)
        let tooMany = Int(1_000 / max(contract.premium, 0.01)) + 5

        XCTAssertThrowsError(try portfolio.buy(contract: contract, quantity: tooMany))
        XCTAssertEqual(portfolio.user.reelCoins, 1_000)
        XCTAssertTrue(portfolio.positions.isEmpty)
    }

    @MainActor
    func testWinningCall_paysIntrinsic_andRaisesProfitAndRank() throws {
        let portfolio = freshAccount()
        let contract = try tradableContract(.call)
        try portfolio.buy(contract: contract, quantity: 10)
        let cost = contract.premium * 10

        // Far enough above the strike to beat the premium on any film the
        // live catalog offers (a deep in-the-money Call can cost 80+ RC).
        let beat = contract.premium / contract.multiplier + 50
        let actual = contract.strikeMillions + beat
        portfolio.settle(movieId: contract.movieId, actualMillions: actual)

        let payout = beat * contract.multiplier * 10
        XCTAssertGreaterThan(payout - cost, 0)
        XCTAssertEqual(portfolio.user.reelCoins, 1_000 - cost + payout, accuracy: 0.001)
        XCTAssertEqual(portfolio.user.lifetimePnL, payout - cost, accuracy: 0.001)
        XCTAssertEqual(portfolio.user.bestProfit ?? 0, payout - cost, accuracy: 0.001)
        XCTAssertEqual(portfolio.user.tier, Tier.forProfit(payout - cost))
        XCTAssertFalse(portfolio.positions[0].isOpen)
    }

    @MainActor
    func testLosingPut_expiresWorthless_andLosesOnlyThePremium() throws {
        let portfolio = freshAccount()
        let contract = try tradableContract(.put)
        try portfolio.buy(contract: contract, quantity: 4)
        let cost = contract.premium * 4

        portfolio.settle(movieId: contract.movieId, actualMillions: contract.strikeMillions + 10)

        XCTAssertEqual(portfolio.user.reelCoins, 1_000 - cost, accuracy: 0.001)
        XCTAssertEqual(portfolio.user.lifetimePnL, -cost, accuracy: 0.001)
        XCTAssertEqual(portfolio.positions[0].settledPayout, 0)
    }

    @MainActor
    func testVoidedMarket_refundsAtCost_withNoProfitOrLoss() throws {
        let portfolio = freshAccount()
        let contract = try tradableContract(.call)
        try portfolio.buy(contract: contract, quantity: 5)

        let refund = portfolio.voidMarket(movieId: contract.movieId)

        XCTAssertEqual(refund, contract.premium * 5, accuracy: 0.001)
        XCTAssertEqual(portfolio.user.reelCoins, 1_000, accuracy: 0.001)
        XCTAssertEqual(portfolio.user.lifetimePnL, 0)
        XCTAssertFalse(portfolio.positions[0].isOpen)
        XCTAssertEqual(portfolio.positions[0].voided, true)
        XCTAssertNil(portfolio.positions[0].actualOWMillions, "not a weekend result")
        XCTAssertEqual(portfolio.voidMarket(movieId: contract.movieId), 0, "never refunds twice")
    }

    @MainActor
    func testRankNeverDrops_afterALosingWeek() throws {
        let portfolio = freshAccount()
        portfolio.mutateUser { $0.lifetimePnL = 3_200 }
        XCTAssertEqual(portfolio.user.tier, .studioHead)
        portfolio.mutateUser { $0.lifetimePnL = 900 }
        XCTAssertEqual(portfolio.user.tier, .studioHead, "Rank follows best profit reached")
    }

    @MainActor
    func testSettlingTwice_neverPaysTwice() throws {
        let portfolio = freshAccount()
        let contract = try tradableContract(.call)
        try portfolio.buy(contract: contract, quantity: 2)
        portfolio.settle(movieId: contract.movieId, actualMillions: contract.strikeMillions + 20)
        let afterFirst = portfolio.user.reelCoins

        portfolio.settle(movieId: contract.movieId, actualMillions: contract.strikeMillions + 20)

        XCTAssertEqual(portfolio.user.reelCoins, afterFirst)
    }

    // MARK: - Weekly cycle

    @MainActor
    func testWeeklyCycle_keepsProfit_andRestoresTheStake() {
        let portfolio = freshAccount()
        rewindWeek(portfolio)
        portfolio.mutateUser { $0.reelCoins = 1_350 }

        portfolio.applyWeeklyCycle()

        XCTAssertEqual(portfolio.user.reelCoins, 1_350, accuracy: 0.001,
                       "350 profit kept through Sunday + a fresh 1,000 Monday")
        XCTAssertEqual(portfolio.user.weeklyStake, 1_000)
        XCTAssertEqual(portfolio.user.lifetimePnL, 0, "The reset never touches profit")
    }

    @MainActor
    func testWeeklyCycle_loserGetsTheStakeBack() {
        let portfolio = freshAccount()
        rewindWeek(portfolio)
        portfolio.mutateUser { $0.reelCoins = 0 }

        portfolio.applyWeeklyCycle()

        XCTAssertEqual(portfolio.user.reelCoins, 1_000, accuracy: 0.001)
    }

    @MainActor
    func testWeeklyCycle_isIdempotent() {
        let portfolio = freshAccount()
        rewindWeek(portfolio)
        portfolio.applyWeeklyCycle()
        let once = portfolio.user.reelCoins

        portfolio.applyWeeklyCycle()
        portfolio.applyWeeklyCycle()

        XCTAssertEqual(portfolio.user.reelCoins, once)
    }

    @MainActor
    func testStakeParkedInATrade_isRepaidFromItsWinnings() throws {
        let portfolio = freshAccount()
        let contract = try tradableContract(.call)
        let quantity = max(1, Int(600 / max(contract.premium, 0.01)))
        try portfolio.buy(contract: contract, quantity: quantity)
        let cost = contract.premium * Double(quantity)

        rewindWeek(portfolio)
        portfolio.applyWeeklyCycle()
        XCTAssertEqual(portfolio.user.reelCoins, 1_000, accuracy: 0.001)
        XCTAssertEqual(portfolio.user.stakeOwed ?? 0, cost, accuracy: 0.001)

        // A clear win whatever the film: beats the premium by $100M.
        let beat = contract.premium / contract.multiplier + 100
        let payout = beat * contract.multiplier * Double(quantity)
        portfolio.settle(movieId: contract.movieId, actualMillions: contract.strikeMillions + beat)

        XCTAssertEqual(portfolio.user.reelCoins, 1_000 + payout - cost, accuracy: 0.001,
                       "The trade repays the stake it held; profit above that is kept")
        XCTAssertEqual(portfolio.user.stakeOwed ?? 0, 0, accuracy: 0.001)
        XCTAssertEqual(portfolio.user.lifetimePnL, payout - cost, accuracy: 0.001)
    }

    // MARK: - Leaderboard, subscriptions, spotlight

    @MainActor
    func testLeaderboard_ranksByProfit_notBalance() {
        let portfolio = freshAccount()
        portfolio.mutateUser { $0.reelCoins = 1_000_000 }
        portfolio.refreshLeaderboard()
        XCTAssertFalse(portfolio.leaderboard.first?.isCurrentUser ?? true, "Coins alone don't rank you")

        portfolio.mutateUser { $0.lifetimePnL = 100_000 }
        portfolio.refreshLeaderboard()
        XCTAssertEqual(portfolio.myRank, 1)
        XCTAssertEqual(portfolio.user.tier, .legend)
    }

    @MainActor
    func testSubscribing_addsNoCoins() {
        let portfolio = freshAccount()
        portfolio.activateMembership(.mogul, isNewPurchase: true)
        XCTAssertEqual(portfolio.user.reelCoins, 1_000)
        XCTAssertEqual(portfolio.user.weeklyAllowance, 1_000)
        portfolio.downgradeToFree()
    }

    @MainActor
    func testTopFiveTrader_getsTheirReviewSpotlighted() throws {
        let portfolio = freshAccount()
        let movie = try XCTUnwrap(MarketService.shared.movies.first)
        portfolio.mutateUser { $0.lifetimePnL = 100_000 }
        portfolio.refreshLeaderboard()

        SocialService.shared.submitReview(movie: movie, headline: "Test headline",
                                          body: "Test body", rating: 4)

        let spotlight = SocialService.shared.spotlightedReviews()
        XCTAssertEqual(spotlight.first?.authorIsCurrentUser, true, "#1 trader leads the spotlight")
    }

    // MARK: - Account deletion

    @MainActor
    func testDeleteAccount_wipesEverything() throws {
        let portfolio = freshAccount()
        let contract = try tradableContract(.call)
        try portfolio.buy(contract: contract, quantity: 1)
        let movie = try XCTUnwrap(MarketService.shared.movies.first)
        SocialService.shared.submitReview(movie: movie, headline: "h", body: "b", rating: 3)

        AuthService.shared.deleteAccount()

        XCTAssertTrue(portfolio.positions.isEmpty)
        XCTAssertEqual(portfolio.user.reelCoins, 1_000)
        XCTAssertEqual(portfolio.user.lifetimePnL, 0)
        XCTAssertFalse(SocialService.shared.hasCurrentUserReview)
        XCTAssertFalse(AuthService.shared.isSignedIn)
    }

    // MARK: - Helpers

    @MainActor
    private func freshAccount() -> PortfolioService {
        OrderBookService.shared.eraseAllData()
        SocialService.shared.removeCurrentUserContent()
        PortfolioService.shared.eraseAllData()
        PortfolioService.shared.refreshLeaderboard()
        return PortfolioService.shared
    }

    /// Pretends the last Sunday reset and Monday stake happened a week ago.
    @MainActor
    private func rewindWeek(_ portfolio: PortfolioService) {
        let weekAgo = Date().addingTimeInterval(-8 * 86_400)
        portfolio.mutateUser {
            $0.lastResetAt = weekAgo
            $0.lastAllowanceAt = weekAgo
        }
    }

    @MainActor
    private func tradableContract(_ side: ContractSide) throws -> Contract {
        let market = MarketService.shared
        for movie in market.movies where movie.isTradingOpen {
            if let contract = market.chain(for: movie.id).first(where: { $0.side == side && $0.premium > 0 }) {
                return contract
            }
        }
        throw XCTSkip("No movie in today's catalog is still trading")
    }
}
