import Foundation
import WidgetKit

/// Writes the WidgetSnapshot into App Group storage every time
/// something the widget cares about changes. The widget target reads
/// via WidgetSharedStorage.read().
///
/// The snapshot struct is duplicated in the widget target folder;
/// they are kept in lockstep by copying the definition. In a real
/// Xcode setup, add both files to both targets via project.yml.
struct AppSideWidgetSnapshot: Codable {
    let updatedAt: Date
    let nextMovieTitle: String
    let nextMoviePoster: String
    let nextMovieOpensIn: Int
    let nextMovieImpliedConsensus: Double
    let topPositionMovie: String?
    let topPositionSideLabel: String?
    let topPositionMark: Double?
    let topPositionEntry: Double?
    let topPositionPnL: Double?
}

@MainActor
enum WidgetSyncService {
    static let appGroup = "group.com.boxcall.shared"
    static let key = "widget.snapshot.v1"

    /// Read from live services, build a snapshot, write to App Group,
    /// then poke WidgetCenter so the timeline reloads.
    static func sync() {
        let market = MarketService.shared
        let portfolio = PortfolioService.shared

        // Next opening = movie with smallest positive daysToRelease.
        let sorted = market.movies
            .filter { $0.daysToRelease >= 0 }
            .sorted { $0.daysToRelease < $1.daysToRelease }
        guard let next = sorted.first else { return }

        // Top position = biggest cost, open only.
        let openPositions = portfolio.positions.filter { $0.isOpen }
        let top = openPositions.max { $0.cost < $1.cost }
        var topMovie: String?
        var topSide: String?
        var topMark: Double?
        var topEntry: Double?
        var topPnL: Double?
        if let p = top, let movie = market.movie(id: p.movieId) {
            let chain = market.chain(for: p.movieId)
            let mark = chain.first { $0.id == p.contractId }?.premium ?? p.entryPremium
            topMovie = movie.title
            topSide = "\(p.side.display) $\(Int(p.strikeMillions))M"
            topMark = mark
            topEntry = p.entryPremium
            topPnL = (mark - p.entryPremium) * Double(p.quantity)
        }

        let snapshot = AppSideWidgetSnapshot(
            updatedAt: Date(),
            nextMovieTitle: next.title,
            nextMoviePoster: next.posterEmoji,
            nextMovieOpensIn: next.daysToRelease,
            nextMovieImpliedConsensus: market.impliedConsensus(for: next.id),
            topPositionMovie: topMovie,
            topPositionSideLabel: topSide,
            topPositionMark: topMark,
            topPositionEntry: topEntry,
            topPositionPnL: topPnL
        )
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
