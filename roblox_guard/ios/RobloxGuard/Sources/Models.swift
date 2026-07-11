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

struct EvidenceItem: Identifiable, Codable, Hashable {
    let id: Int
    let kind: String        // profile_screenshot | data_snapshot | parent_upload
    let sha256: String
    let note: String
    let capturedAt: String
    let filename: String

    enum CodingKeys: String, CodingKey {
        case id, kind, sha256, note, filename
        case capturedAt = "captured_at"
    }

    var kindLabel: String {
        switch kind {
        case "profile_screenshot": return "Profile screenshot (auto)"
        case "data_snapshot": return "Data snapshot (auto)"
        case "parent_upload": return "Your screenshot"
        default: return kind
        }
    }
}

struct DangerEntry: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let summary: String
    let progression: [String]
}

struct EducationContent: Codable {
    let dangers: [DangerEntry]
    let behavioralSigns: [String]
    let immediateRedFlags: [String]
    let responsePlaybook: [String]

    enum CodingKeys: String, CodingKey {
        case dangers
        case behavioralSigns = "behavioral_signs"
        case immediateRedFlags = "immediate_red_flags"
        case responsePlaybook = "response_playbook"
    }
}
