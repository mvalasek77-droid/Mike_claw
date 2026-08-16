import Foundation

/// One place that owns "when do coins refill?".
///
/// Semantics: every Monday at 00:00 in the user's local time zone,
/// every account gets its membership's weekly allowance. If a user
/// misses a Monday (app closed for a week), they still get exactly
/// one allowance on next launch — never a stacked backlog.
///
/// This deliberately mirrors real box-office cadence: opening
/// weekends settle Monday morning, and so do BoxCall balances.
enum RefillClock {
    /// The most recent Monday-at-midnight (local), on or before `now`.
    static func lastMonday(before now: Date = Date()) -> Date {
        let cal = Calendar.current
        // Move forward off `now` by 1 minute to guarantee we get a
        // Monday STRICTLY before, then look backward.
        var comps = DateComponents()
        comps.weekday = 2   // Monday (Sunday = 1)
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return cal.nextDate(
            after: now.addingTimeInterval(60),
            matching: comps,
            matchingPolicy: .nextTime,
            direction: .backward
        ) ?? now
    }

    /// The next Monday-at-midnight (local) strictly after `now`.
    static func nextMonday(after now: Date = Date()) -> Date {
        let cal = Calendar.current
        var comps = DateComponents()
        comps.weekday = 2
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return cal.nextDate(
            after: now,
            matching: comps,
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(7 * 86400)
    }

    /// Short human countdown to the next refill. "2d 14h" / "6h 23m" / "12m".
    static func countdownString(from now: Date = Date()) -> String {
        let seconds = nextMonday(after: now).timeIntervalSince(now)
        if seconds <= 0 { return "any moment" }
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if days >= 1 { return "\(days)d \(hours)h" }
        if hours >= 1 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Localized long form, e.g. "Monday, Aug 25 at 12:00 AM".
    static func nextMondayFormatted(from now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return f.string(from: nextMonday(after: now))
    }
}
