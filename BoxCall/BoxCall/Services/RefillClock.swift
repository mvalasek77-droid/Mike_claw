import Foundation

/// One place that owns the weekly coin cycle, in the user's local time.
///
/// - Friday: a movie opens and trading on it locks.
/// - Sunday 00:00: the week's stake is taken back. Profit stays.
/// - Sunday afternoon: opening weekends settle on the studios' estimate.
/// - Monday 00:00: a fresh stake lands.
///
/// A user who misses a week gets exactly one reset and one stake on
/// next launch — never a stacked backlog.
enum RefillClock {
    private static let sunday = 1
    private static let monday = 2

    /// The most recent Monday-at-midnight (local), on or before `now`.
    static func lastMonday(before now: Date = Date()) -> Date {
        last(weekday: monday, before: now)
    }

    /// The next Monday-at-midnight (local) strictly after `now`.
    static func nextMonday(after now: Date = Date()) -> Date {
        next(weekday: monday, after: now)
    }

    /// The most recent Sunday-at-midnight (local), on or before `now`.
    static func lastSunday(before now: Date = Date()) -> Date {
        last(weekday: sunday, before: now)
    }

    /// The next Sunday-at-midnight (local) strictly after `now`.
    static func nextSunday(after now: Date = Date()) -> Date {
        next(weekday: sunday, after: now)
    }

    private static func midnight(weekday: Int) -> DateComponents {
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return comps
    }

    private static func last(weekday: Int, before now: Date) -> Date {
        // Step 1 minute past `now` so a boundary exactly at `now` counts.
        Calendar.current.nextDate(
            after: now.addingTimeInterval(60),
            matching: midnight(weekday: weekday),
            matchingPolicy: .nextTime,
            direction: .backward
        ) ?? now
    }

    private static func next(weekday: Int, after now: Date) -> Date {
        Calendar.current.nextDate(
            after: now,
            matching: midnight(weekday: weekday),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(7 * 86400)
    }

    /// Short human countdown to the next Monday stake. "2d 14h" / "6h 23m" / "12m".
    static func countdownString(from now: Date = Date()) -> String {
        countdown(to: nextMonday(after: now), from: now)
    }

    /// Short human countdown to the next Sunday reset.
    static func resetCountdownString(from now: Date = Date()) -> String {
        countdown(to: nextSunday(after: now), from: now)
    }

    private static func countdown(to target: Date, from now: Date) -> String {
        let seconds = target.timeIntervalSince(now)
        if seconds <= 0 { return "any moment" }
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if days >= 1 { return "\(days)d \(hours)h" }
        if hours >= 1 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return f
    }()

    /// Localized long form, e.g. "Monday, Aug 25 at 12:00 AM".
    static func nextMondayFormatted(from now: Date = Date()) -> String {
        dayFormatter.string(from: nextMonday(after: now))
    }
}

/// The Sunday reset rule, kept pure so it can be tested.
enum WeeklyReset {
    /// The week's stake goes back and profit stays. Profit is kept as cash
    /// first; whatever part of the stake is riding on trades that are still
    /// running becomes `owed`, repaid from those trades' proceeds later.
    /// - Parameters:
    ///   - openCost: cost basis of every open position.
    ///   - owed: stake already claimed against those positions at an earlier reset.
    static func reset(cash: Double, openCost: Double, owed: Double,
                      stake: Double) -> (cash: Double, owed: Double) {
        let equity = cash + max(openCost - owed, 0)
        let profit = max(equity - stake, 0)
        let keptCash = min(cash, profit)
        let reclaimed = min(equity, stake)
        let fromCash = cash - keptCash
        return (keptCash, owed + max(reclaimed - fromCash, 0))
    }

    /// Proceeds from a trade that was running at the reset first repay the
    /// stake it held, up to its cost. Returns (coins credited, owed left).
    static func settleCarried(proceeds: Double, cost: Double,
                              owed: Double) -> (credited: Double, owed: Double) {
        let claim = min(owed, cost)
        return (proceeds - min(proceeds, claim), owed - claim)
    }

    /// Coins added on Monday: tops the stake back up to the tier amount.
    static func mondayGrant(allowance: Double, stakeStillHeld: Double) -> Double {
        max(allowance - stakeStillHeld, 0)
    }
}
