import Foundation
import ActivityKit

/// Attributes + state for the opening-day Live Activity.
/// Attributes are set-once at start; ContentState updates as the
/// mark ticks and (post-settlement) once the actual gross posts.
struct OpeningLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var impliedConsensusM: Double
        var yourPositionSide: String       // "CALL $12M" / "PUT $18M"
        var yourPositionMark: Double
        var yourPositionEntry: Double
        var yourPositionPnL: Double
        var actualOpeningM: Double?        // set once settled
    }

    let movieId: String
    let movieTitle: String
    let moviePoster: String
    let opensAt: Date
}

@MainActor
enum LiveActivityService {
    private static var current: Activity<OpeningLiveActivityAttributes>?

    /// Start an activity for a movie you're holding a position on.
    /// The system displays it on the Lock Screen and — on iPhone 14 Pro
    /// and up — in the Dynamic Island.
    static func start(movie: Movie, position: Position) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let mark = MarketService.shared.chain(for: movie.id)
            .first(where: { $0.id == position.contractId })?.premium ?? position.entryPremium
        let attrs = OpeningLiveActivityAttributes(
            movieId: movie.id,
            movieTitle: movie.title,
            moviePoster: movie.posterEmoji,
            opensAt: movie.releaseDate
        )
        let state = OpeningLiveActivityAttributes.ContentState(
            impliedConsensusM: MarketService.shared.impliedConsensus(for: movie.id),
            yourPositionSide: "\(position.side.display) $\(Int(position.strikeMillions))M",
            yourPositionMark: mark,
            yourPositionEntry: position.entryPremium,
            yourPositionPnL: (mark - position.entryPremium) * Double(position.quantity),
            actualOpeningM: nil
        )
        do {
            current = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: movie.releaseDate.addingTimeInterval(4 * 86400))
            )
        } catch {
            // Silently drop — Live Activities are a nice-to-have.
        }
    }

    /// Called by MarketService each tick if a movie is currently
    /// featured in a Live Activity — updates the in-flight state.
    static func update(movie: Movie, position: Position) {
        guard let activity = current, activity.attributes.movieId == movie.id else { return }
        let chain = MarketService.shared.chain(for: movie.id)
        let mark = chain.first(where: { $0.id == position.contractId })?.premium ?? position.entryPremium
        let state = OpeningLiveActivityAttributes.ContentState(
            impliedConsensusM: MarketService.shared.impliedConsensus(for: movie.id),
            yourPositionSide: "\(position.side.display) $\(Int(position.strikeMillions))M",
            yourPositionMark: mark,
            yourPositionEntry: position.entryPremium,
            yourPositionPnL: (mark - position.entryPremium) * Double(position.quantity),
            actualOpeningM: position.actualOWMillions
        )
        Task {
            await activity.update(.init(state: state, staleDate: movie.releaseDate.addingTimeInterval(4 * 86400)))
        }
    }

    static func end(final: OpeningLiveActivityAttributes.ContentState? = nil) {
        guard let activity = current else { return }
        Task {
            if let final {
                await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(3600)))
            } else {
                await activity.end(dismissalPolicy: .immediate)
            }
            current = nil
        }
    }
}
