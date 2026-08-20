import Foundation

/// Data written by the main app into App Group UserDefaults so the
/// widget process can read it without touching the app's live services.
/// Kept intentionally small — WidgetKit reads limited snapshots.
struct WidgetSnapshot: Codable {
    let updatedAt: Date

    // "Next opening" data
    let nextMovieTitle: String
    let nextMoviePoster: String       // emoji fallback
    let nextMovieOpensIn: Int         // days
    let nextMovieImpliedConsensus: Double

    // "Top position" data (nil if no open positions)
    let topPositionMovie: String?
    let topPositionSideLabel: String? // "CALL $12M" / "PUT $18M"
    let topPositionMark: Double?
    let topPositionEntry: Double?
    let topPositionPnL: Double?

    static let placeholder = WidgetSnapshot(
        updatedAt: Date(),
        nextMovieTitle: "Neon Requiem",
        nextMoviePoster: "🌃",
        nextMovieOpensIn: 5,
        nextMovieImpliedConsensus: 12.4,
        topPositionMovie: "Neon Requiem",
        topPositionSideLabel: "CALL $12M",
        topPositionMark: 3.10,
        topPositionEntry: 2.80,
        topPositionPnL: 8.5
    )
}

enum WidgetSharedStorage {
    /// App Group id shared between the app and the widget target.
    /// Configure the same group id in both entitlements files.
    static let appGroup = "group.com.boxcall.shared"
    static let key = "widget.snapshot.v1"

    static func read() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .placeholder }
        return snapshot
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
