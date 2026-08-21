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
}
