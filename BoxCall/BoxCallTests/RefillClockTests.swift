import XCTest
@testable import BoxCall

final class RefillClockTests: XCTestCase {
    private func makeDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var dc = DateComponents()
        dc.year = y; dc.month = m; dc.day = d; dc.hour = h
        return Calendar.current.date(from: dc)!
    }

    func testNextMonday_fromWednesday_isSameWeekMonday_plus5() {
        // Wednesday 2026-08-19 → next Monday should be 2026-08-24
        let wed = makeDate(2026, 8, 19)
        let next = RefillClock.nextMonday(after: wed)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .weekday], from: next)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 8)
        XCTAssertEqual(comps.day, 24)
        XCTAssertEqual(comps.weekday, 2)   // Monday
    }

    func testLastMonday_fromWednesday_isPreviousMonday() {
        // Wed 2026-08-19 → last Monday should be 2026-08-17
        let wed = makeDate(2026, 8, 19)
        let last = RefillClock.lastMonday(before: wed)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: last)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 8)
        XCTAssertEqual(comps.day, 17)
    }

    func testNextMonday_fromMondayMidnight_isNextWeek() {
        // Monday 2026-08-17 at 00:00 → next Monday should be a week later
        var dc = DateComponents()
        dc.year = 2026; dc.month = 8; dc.day = 17; dc.hour = 0; dc.minute = 0
        let mondayMidnight = Calendar.current.date(from: dc)!
        let next = RefillClock.nextMonday(after: mondayMidnight)
        let day = Calendar.current.component(.day, from: next)
        // Should not be same day.
        XCTAssertNotEqual(day, 17)
    }

    func testCountdownString_nonEmpty() {
        let s = RefillClock.countdownString()
        XCTAssertFalse(s.isEmpty)
    }

    func testLastSunday_fromWednesday_isPreviousSunday() {
        // Wed 2026-08-19 → last Sunday 2026-08-16
        let last = RefillClock.lastSunday(before: makeDate(2026, 8, 19))
        let comps = Calendar.current.dateComponents([.month, .day, .weekday, .hour], from: last)
        XCTAssertEqual(comps.month, 8)
        XCTAssertEqual(comps.day, 16)
        XCTAssertEqual(comps.weekday, 1)
        XCTAssertEqual(comps.hour, 0)
    }

    func testSundayAfternoon_resetIsToday_mondayIsLastWeek() {
        let sun = makeDate(2026, 8, 23, 15)
        XCTAssertEqual(Calendar.current.component(.day, from: RefillClock.lastSunday(before: sun)), 23)
        XCTAssertEqual(Calendar.current.component(.day, from: RefillClock.lastMonday(before: sun)), 17)
    }
}

final class WeeklyResetTests: XCTestCase {
    func testWinner_keepsOnlyProfit() {
        let r = WeeklyReset.reset(cash: 1_350, openCost: 0, owed: 0, stake: 1_000)
        XCTAssertEqual(r.cash, 350)
        XCTAssertEqual(r.owed, 0)
    }

    func testLoser_keepsNothing_owesNothing() {
        let r = WeeklyReset.reset(cash: 120, openCost: 0, owed: 0, stake: 1_000)
        XCTAssertEqual(r.cash, 0)
        XCTAssertEqual(r.owed, 0)
    }

    func testStakeRidingOnTrades_isOwedNotForgiven() {
        // 600 cash + 800 on an unreleased movie: 400 profit kept as cash,
        // 200 of stake taken from cash, 800 claimed against the trade.
        let r = WeeklyReset.reset(cash: 600, openCost: 800, owed: 0, stake: 1_000)
        XCTAssertEqual(r.cash, 400)
        XCTAssertEqual(r.owed, 800)
    }

    func testParkingWholeStake_cannotDodgeTheReset() {
        let r = WeeklyReset.reset(cash: 0, openCost: 1_000, owed: 0, stake: 1_000)
        XCTAssertEqual(r.cash, 0)
        XCTAssertEqual(r.owed, 1_000)
    }

    func testAlreadyClaimedTrade_isNotClaimedTwice() {
        let r = WeeklyReset.reset(cash: 1_300, openCost: 1_000, owed: 1_000, stake: 1_000)
        XCTAssertEqual(r.cash, 300)
        XCTAssertEqual(r.owed, 1_000)
    }

    func testCarriedWinner_repaysStake_keepsProfit() {
        let r = WeeklyReset.settleCarried(proceeds: 1_500, cost: 1_000, owed: 1_000)
        XCTAssertEqual(r.credited, 500)
        XCTAssertEqual(r.owed, 0)
    }

    func testCarriedLoser_owesNothing() {
        let r = WeeklyReset.settleCarried(proceeds: 0, cost: 1_000, owed: 1_000)
        XCTAssertEqual(r.credited, 0)
        XCTAssertEqual(r.owed, 0)
    }

    func testMondayGrant_fullAfterReset_topUpOtherwise() {
        XCTAssertEqual(WeeklyReset.mondayGrant(allowance: 1_000, stakeStillHeld: 0), 1_000)
        XCTAssertEqual(WeeklyReset.mondayGrant(allowance: 1_000, stakeStillHeld: 1_000), 0)
        XCTAssertEqual(WeeklyReset.mondayGrant(allowance: 1_500, stakeStillHeld: 1_000), 500)
    }
}
