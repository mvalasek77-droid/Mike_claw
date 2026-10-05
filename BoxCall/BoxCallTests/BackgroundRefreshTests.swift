import XCTest
@testable import BoxCall

final class BackgroundRefreshTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testHeldFilmWaitingOnItsNumber_checksAgainWithinTheHour() {
        let now = at(2026, 10, 4, 11) // Sunday morning
        XCTAssertEqual(BackgroundRefresh.nextCheck(now: now, awaitingResult: true, calendar: calendar),
                       now.addingTimeInterval(3_600))
    }

    func testNothingWaiting_checksSundayAfternoon() {
        let wednesday = at(2026, 10, 7, 9)
        XCTAssertEqual(BackgroundRefresh.nextCheck(now: wednesday, awaitingResult: false, calendar: calendar),
                       at(2026, 10, 11, 13))
    }

    func testSundayEvening_rollsToNextSunday() {
        let sundayNight = at(2026, 10, 4, 20)
        XCTAssertEqual(BackgroundRefresh.nextCheck(now: sundayNight, awaitingResult: false, calendar: calendar),
                       at(2026, 10, 11, 13))
    }
}
