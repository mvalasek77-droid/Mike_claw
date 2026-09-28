import Foundation

/// The simulated rival traders on the leaderboard. Their total profit moves
/// every week — the same numbers on every device and every launch — so
/// holding the #1 spot takes steady winning, not one lucky weekend.
enum RivalLeague {
    struct Rival {
        let handle: String
        let tier: Tier
        let startingProfit: Double
        /// Average weekly result; each week swings around it.
        let weeklyEdge: Double
        let winRate: Double
    }

    static let rivals: [Rival] = [
        // Tuned so the top 5 takes a good weekend or two (+300–500 RC) and
        // #1 takes a sustained run of winning weeks.
        .init(handle: "popcornshark", tier: .studioHead, startingProfit: 2_400, weeklyEdge: 95, winRate: 0.62),
        .init(handle: "indieyoda",    tier: .producer,   startingProfit: 1_500, weeklyEdge: 75, winRate: 0.58),
        .init(handle: "openingnight", tier: .insider,    startingProfit: 1_100, weeklyEdge: 55, winRate: 0.51),
        .init(handle: "greenlight",   tier: .analyst,    startingProfit: 680,   weeklyEdge: 40, winRate: 0.54),
        .init(handle: "marqueemaven", tier: .insider,    startingProfit: 520,   weeklyEdge: 35, winRate: 0.47),
        .init(handle: "trailerbait",  tier: .analyst,    startingProfit: 300,   weeklyEdge: 25, winRate: 0.42),
    ]

    /// League week 0 began Monday, Sept 7 2026.
    static let epoch: Date = DateComponents(calendar: .current, year: 2026, month: 9, day: 7).date
        ?? Date(timeIntervalSince1970: 1_788_739_200)

    static func week(at now: Date) -> Int {
        max(0, Calendar.current.dateComponents([.weekOfYear], from: epoch, to: now).weekOfYear ?? 0)
    }

    static func weeklyPnL(_ rival: Rival, week: Int) -> Double {
        var rng = SeededGenerator(seed: "\(rival.handle)#\(week)")
        return (rival.weeklyEdge + rng.jitter(max(rival.weeklyEdge, 40) * 3)).rounded()
    }

    static func profit(_ rival: Rival, at now: Date) -> Double {
        let w = week(at: now)
        guard w > 0 else { return rival.startingProfit }
        return (1...w).reduce(rival.startingProfit) { $0 + weeklyPnL(rival, week: $1) }
    }

    static func lastWeekPnL(_ rival: Rival, at now: Date) -> Double {
        let w = week(at: now)
        return w > 0 ? weeklyPnL(rival, week: w) : 0
    }
}

/// Quarterly seasons. The #1 trader by total profit when a season ends is
/// crowned that season's Oracle.
enum Season {
    static func name(at date: Date) -> String {
        let cal = Calendar.current
        let season: String
        switch cal.component(.month, from: date) {
        case 1...3:  season = "Winter"
        case 4...6:  season = "Spring"
        case 7...9:  season = "Summer"
        default:     season = "Fall"
        }
        return "\(season) \(cal.component(.year, from: date))"
    }

    static func end(after date: Date) -> Date? {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let endMonth = ((month - 1) / 3 + 1) * 3 % 12 + 1
        let year = cal.component(.year, from: date) + (endMonth == 1 ? 1 : 0)
        return cal.date(from: DateComponents(year: year, month: endMonth, day: 1))
    }
}
