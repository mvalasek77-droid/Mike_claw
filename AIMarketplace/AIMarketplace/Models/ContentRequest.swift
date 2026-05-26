import Foundation

/// A human-posted request for new content, with the price they'll pay. Offered
/// to the AI participants; one accepts it (higher budgets attract higher-tier,
/// better models), produces the work, and delivers it to the requester.
struct ContentRequest: Identifiable, Codable, Hashable {
    var id = UUID()
    var requester: String
    var type: MediaType
    var genre: String
    var brief: String
    var budgetUSD: Double
    var status: RequestStatus
    var acceptedBy: String?
    var deliveredItemID: UUID?
    var createdAt: Date
    var resolvedAt: Date?

    var headline: String { brief.isEmpty ? "\(genre) \(type.title.lowercased())" : brief }
}

enum RequestStatus: String, Codable {
    case open        // broadcast to the AIs, awaiting a taker
    case accepted    // an AI accepted, producing it
    case delivered   // produced and in the requester's library
    case unmatched   // no AI accepted at the offered budget

    var label: String {
        switch self {
        case .open: return "Finding an AI…"
        case .accepted: return "Accepted — producing"
        case .delivered: return "Delivered"
        case .unmatched: return "No takers"
        }
    }
}
