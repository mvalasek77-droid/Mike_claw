import Foundation

struct Child: Identifiable, Codable, Hashable {
    let id: Int
    let robloxUserId: Int
    let robloxUsername: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case robloxUserId = "roblox_user_id"
        case robloxUsername = "roblox_username"
        case displayName = "display_name"
    }
}

enum AlertSeverity: String, Codable, CaseIterable {
    case info, watch, elevated

    var label: String {
        switch self {
        case .info: return "Info"
        case .watch: return "Worth a look"
        case .elevated: return "Talk soon"
        }
    }
}

struct SafetyAlert: Identifiable, Codable, Hashable {
    let id: Int
    let type: String
    let severity: AlertSeverity
    let title: String
    let facts: [String]
    let guidance: String
    let subjectUsername: String?
    let observedAt: String
    let acknowledged: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, severity, title, facts, guidance, acknowledged
        case subjectUsername = "subject_username"
        case observedAt = "observed_at"
    }
}

struct SafetyResource: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let url: String
    let description: String
}
