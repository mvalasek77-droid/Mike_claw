import XCTest
@testable import BoxCall

final class RivalLeagueTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testRivalProfit_isSameOnEveryCall() {
        let rival = RivalLeague.rivals[0]
        let now = date(2026, 11, 3)
        XCTAssertEqual(RivalLeague.profit(rival, at: now), RivalLeague.profit(rival, at: now))
    }

    func testRivalProfit_beforeLeagueStart_isStartingProfit() {
        let rival = RivalLeague.rivals[0]
        XCTAssertEqual(RivalLeague.profit(rival, at: date(2026, 9, 1)), rival.startingProfit)
    }

    func testRivalProfit_movesByLastWeeksResult() {
        let rival = RivalLeague.rivals[1]
        let thisWeek = date(2026, 10, 14)
        let lastWeek = date(2026, 10, 7)
        XCTAssertEqual(RivalLeague.profit(rival, at: thisWeek) - RivalLeague.profit(rival, at: lastWeek),
                       RivalLeague.lastWeekPnL(rival, at: thisWeek), accuracy: 0.001)
    }

    func testSeasonEnd_rollsIntoNextYearAfterFall() {
        let end = Season.end(after: date(2026, 11, 20))!
        let c = Calendar.current.dateComponents([.year, .month, .day], from: end)
        XCTAssertEqual(c.year, 2027)
        XCTAssertEqual(c.month, 1)
        XCTAssertEqual(c.day, 1)
    }

    func testSeasonEnd_summerEndsOctoberFirst() {
        let end = Season.end(after: date(2026, 8, 2))!
        XCTAssertEqual(Calendar.current.component(.month, from: end), 10)
    }

    func testRanks_followProfitThresholds() {
        XCTAssertEqual(Tier.forProfit(-50), .rookie)
        XCTAssertEqual(Tier.forProfit(249), .rookie)
        XCTAssertEqual(Tier.forProfit(250), .analyst)
        XCTAssertEqual(Tier.forProfit(750), .insider)
        XCTAssertEqual(Tier.forProfit(3_000), .studioHead)
        XCTAssertEqual(Tier.forProfit(10_000), .legend)
    }

    func testEveryPlan_tradesTheSameStake() {
        let stakes = Set(Membership.allCases.map(\.weeklyAllowance))
        XCTAssertEqual(stakes, [StartingGrant.reelCoins])
    }

    /// Must agree with the pipeline's `title_key`, or results never match films.
    func testTitleKey_matchesThePipeline() {
        XCTAssertEqual(Movie.titleKey("Spider-Man: Brand New Day"), "spider man brand new day")
        XCTAssertEqual(Movie.titleKey("  Avengers:  Endgame Encore "), "avengers endgame encore")
        XCTAssertEqual(Movie.titleKey("Amélie"), "amelie")
    }

    func testSeasonName() {
        XCTAssertEqual(Season.name(at: date(2026, 9, 28)), "Summer 2026")
        XCTAssertEqual(Season.name(at: date(2026, 10, 1)), "Fall 2026")
    }
}
