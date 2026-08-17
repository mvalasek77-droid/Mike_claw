import Foundation

/// View history: which posts the current user has already opened, used to
/// render a "Recently viewed" list and the feed's caught-up marker.
protocol HistoryService: Sendable {
    func recordView(postID: UUID) async throws
    /// All viewed post IDs, most-recently-viewed first.
    func viewedPostIDs() async throws -> [UUID]
}

/// Deterministic in-memory view history for previews, tests, and offline demo.
actor MockHistoryService: HistoryService {
    private var viewedInOrder: [UUID] = []
    /// Caps growth so a long demo session doesn't accumulate unbounded state.
    private let limit = 200

    func recordView(postID: UUID) async throws {
        viewedInOrder.removeAll { $0 == postID }
        viewedInOrder.insert(postID, at: 0)
        if viewedInOrder.count > limit { viewedInOrder.removeLast() }
    }

    func viewedPostIDs() async throws -> [UUID] {
        viewedInOrder
    }
}
