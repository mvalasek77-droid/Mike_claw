import Foundation

/// The backend's launch audit, as the phone reads it.
struct ReleaseReadinessRun: Hashable {
    var releaseGate: String
    var score: Int
    var summary: String
    var nextActions: [String]
    var items: [ReleaseReadinessItem]

    var isReadyForTestFlight: Bool { releaseGate == "ready_for_testflight" }

    init(json: [String: Any]) {
        releaseGate = json["release_gate"] as? String ?? "needs_setup"
        score = json["score"] as? Int ?? 0
        summary = json["summary"] as? String ?? ""
        nextActions = json["next_actions"] as? [String] ?? []
        items = ((json["items"] as? [[String: Any]]) ?? []).map(ReleaseReadinessItem.init(json:))
    }
}

struct ReleaseReadinessItem: Identifiable, Hashable {
    var key: String
    var title: String
    var status: String
    var detail: String
    var action: String
    var required: Bool
    var id: String { key }

    init(json: [String: Any]) {
        key = json["key"] as? String ?? UUID().uuidString
        title = json["title"] as? String ?? key
        status = json["status"] as? String ?? "needs_setup"
        detail = json["detail"] as? String ?? ""
        action = json["action"] as? String ?? ""
        required = json["required"] as? Bool ?? false
    }
}
