import BackgroundTasks
import Foundation

/// Lets iOS wake BoxCall in the background to settle positions, so a
/// Sunday result pays out (and its notification arrives) even if the
/// player never opens the app that day.
///
/// iOS decides the exact moment: `earliestBeginDate` is a floor, not a
/// promise. Whatever the system does, the next launch or return to the
/// foreground still settles, and every player settles on the same frozen
/// number either way.
enum BackgroundRefresh {
    /// Also listed under BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let identifier = "com.boxcall.app.settle"

    /// One background pass: the weekly cycle first (as at launch), then
    /// settlement, then the widget. Ends by booking the next pass.
    @MainActor
    static func run() async {
        PortfolioService.shared.applyWeeklyCycle()
        await SettlementService.shared.checkAndSettle()
        WidgetSyncService.sync()
        schedule()
    }

    /// Books the next background pass. Resubmitting replaces the pending
    /// request, so calling this often is harmless.
    @MainActor
    static func schedule(now: Date = Date()) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = nextCheck(now: now,
                                              awaitingResult: awaitingResult(now: now))
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Hourly while a held film has opened and is waiting on its number;
    /// otherwise Sunday at 1 PM local, when studios start reporting.
    static func nextCheck(now: Date, awaitingResult: Bool,
                          calendar: Calendar = .current) -> Date {
        if awaitingResult { return now.addingTimeInterval(60 * 60) }
        let sundayOnePM = DateComponents(hour: 13, minute: 0, weekday: 1)
        return calendar.nextDate(after: now, matching: sundayOnePM,
                                 matchingPolicy: .nextTime) ?? now.addingTimeInterval(6 * 60 * 60)
    }

    /// An open position on a film that has already opened.
    @MainActor
    private static func awaitingResult(now: Date) -> Bool {
        let opened = Set(MarketService.shared.movies.filter { $0.opensAt <= now }.map(\.id))
        return PortfolioService.shared.positions.contains { $0.isOpen && opened.contains($0.movieId) }
    }
}
