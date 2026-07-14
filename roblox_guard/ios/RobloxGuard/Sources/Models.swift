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

struct TermExplainer: Codable, Hashable {
    let term: String
    let definition: String
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
    /// Plain-language definitions for every Roblox term this alert uses,
    /// computed server-side so parents never hit unexplained jargon.
    let explainers: [TermExplainer]?

    enum CodingKeys: String, CodingKey {
        case id, type, severity, title, facts, guidance, acknowledged, explainers
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

struct ProtectionStatus: Codable {
    struct FeedStatus: Codable {
        let version: Int
        let updatedAt: String
        let source: String

        enum CodingKeys: String, CodingKey {
            case version, source
            case updatedAt = "updated_at"
        }
    }

    struct IntelRun: Codable {
        let ranAt: String
        let findingsCount: Int
        let applied: Bool

        enum CodingKeys: String, CodingKey {
            case applied
            case ranAt = "ran_at"
            case findingsCount = "findings_count"
        }
    }

    let feed: FeedStatus
    let lastIntelRun: IntelRun?
    let analyzer: String
    let autoApply: Bool
    let sourcesConfigured: Int

    enum CodingKeys: String, CodingKey {
        case feed, analyzer
        case lastIntelRun = "last_intel_run"
        case autoApply = "auto_apply"
        case sourcesConfigured = "sources_configured"
    }
}

struct BasicsEntry: Identifiable, Codable, Hashable {
    let id: String
    let question: String
    let answer: String
}

struct EducationContent: Codable {
    let robloxBasics: [BasicsEntry]
    let dangers: [DangerEntry]
    let behavioralSigns: [String]
    let immediateRedFlags: [String]
    let responsePlaybook: [String]
    let glossary: [TermExplainer]

    enum CodingKeys: String, CodingKey {
        case dangers, glossary
        case robloxBasics = "roblox_basics"
        case behavioralSigns = "behavioral_signs"
        case immediateRedFlags = "immediate_red_flags"
        case responsePlaybook = "response_playbook"
    }
}
