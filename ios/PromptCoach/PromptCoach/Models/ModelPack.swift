import Foundation

/// Decodes the bundled `model-pack.json` — the versioned data file that drives
/// all coaching. Ships in the app and can be refreshed from a URL without an
/// App Store update (bump `pack_version`).
struct ModelPack: Codable {
    let packVersion: String
    let crossModelRules: [String]
    let efficiencyRules: [String]
    let techniques: Techniques
    let taskPlaybooks: TaskPlaybooks
    let refusalHandling: RefusalHandling
    let advancedFeatures: AdvancedFeatures
    let models: [ModelProfile]
    let recommender: Recommender

    enum CodingKeys: String, CodingKey {
        case packVersion = "pack_version"
        case crossModelRules = "cross_model_rules"
        case efficiencyRules = "efficiency_rules"
        case techniques
        case taskPlaybooks = "task_playbooks"
        case refusalHandling = "refusal_handling"
        case advancedFeatures = "advanced_features"
        case models
        case recommender
    }

    func model(id: String) -> ModelProfile? { models.first { $0.id == id } }
    func technique(id: String) -> Technique? { techniques.library.first { $0.id == id } }
    func playbook(task: String) -> Playbook? { taskPlaybooks.playbooks.first { $0.task == task } }

    /// Loads the pack bundled with the app. Traps only on a corrupt build —
    /// the JSON is validated in CI, so a decode failure means a broken bundle.
    static func loadBundled() -> ModelPack {
        guard let url = Bundle.main.url(forResource: "model-pack", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("model-pack.json missing from bundle")
        }
        do {
            return try JSONDecoder().decode(ModelPack.self, from: data)
        } catch {
            fatalError("model-pack.json failed to decode: \(error)")
        }
    }
}

struct ModelProfile: Codable, Identifiable, Hashable {
    let name: String
    let id: String
    let accent: String
    let priceInPerMtok: Double
    let priceOutPerMtok: Double
    let priceNote: String?
    let oneLiner: String
    let temperament: String
    let strengths: [String]
    let defaultEffort: String?
    let bestFit: String
    /// Techniques that are counterproductive on this model and must NOT be
    /// applied. Opus 5, for example, self-verifies — adding a self-check
    /// instruction causes over-verification and burns tokens for no gain.
    let suppressTechniques: [String]?
    /// Verbatim prompt lines this model specifically benefits from.
    let extraInstructions: [String]?
    let rewriteRules: [String]?
    let doList: [String]?
    let dontList: [String]?
    let apiFacts: APIFacts?

    enum CodingKeys: String, CodingKey {
        case name, id, accent, oneLiner = "one_liner", temperament, strengths
        case priceInPerMtok = "price_in_per_mtok"
        case priceOutPerMtok = "price_out_per_mtok"
        case priceNote = "price_note"
        case defaultEffort = "default_effort"
        case bestFit = "best_fit"
        case suppressTechniques = "suppress_techniques"
        case extraInstructions = "extra_instructions"
        case rewriteRules = "rewrite_rules"
        case doList = "do"
        case dontList = "dont"
        case apiFacts = "api_facts"
    }

    var suppressed: Set<String> { Set(suppressTechniques ?? []) }
    var extras: [String] { extraInstructions ?? [] }

    var priceLabel: String { "$\(fmt(priceInPerMtok)) / $\(fmt(priceOutPerMtok)) per M" }

    /// Short display name without the "Claude " prefix, for chips.
    var shortName: String {
        name.replacingOccurrences(of: "Claude ", with: "")
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
}

/// The hard API facts for a model — what it accepts and rejects. The coach
/// must never emit advice that contradicts these (e.g. suggesting an effort
/// level for Haiku 4.5, which has none).
struct APIFacts: Codable, Hashable {
    let thinkingWhenOmitted: String?
    let explicitDisableAllowed: Bool?
    let disableThinkingEffortCeiling: String?
    let rejects: [String]?
    let effortLevels: [String]?
    let contextWindow: Int?
    let maxOutput: Int?
    let promptCacheMinTokens: Int?
    let dataRetention: String?
    let refusalPossible: Bool?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case thinkingWhenOmitted = "thinking_when_omitted"
        case explicitDisableAllowed = "explicit_disable_allowed"
        case disableThinkingEffortCeiling = "disable_thinking_effort_ceiling"
        case rejects
        case effortLevels = "effort_levels"
        case contextWindow = "context_window"
        case maxOutput = "max_output"
        case promptCacheMinTokens = "prompt_cache_min_tokens"
        case dataRetention = "data_retention"
        case refusalPossible = "refusal_possible"
        case notes
    }

    var supportsEffort: Bool { !(effortLevels ?? []).isEmpty }
}

struct Techniques: Codable {
    let library: [Technique]
    let retired: [String]
}

struct Technique: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let when: String
}

struct TaskPlaybooks: Codable {
    let playbooks: [Playbook]
}

struct Playbook: Codable, Hashable {
    let task: String
    let recommend: String
    let techniques: [String]
    let output: String
}

struct Recommender: Codable {
    let `default`: String
    let rules: [RecommenderRule]
    let tieBreaker: String
    enum CodingKeys: String, CodingKey { case `default`, rules, tieBreaker = "tie_breaker" }
}

struct RecommenderRule: Codable {
    let model: String
    let when: String
    let why: String
}

struct RefusalHandling: Codable {
    let falsePositiveFixes: [String]
    let outOfScope: String
    enum CodingKeys: String, CodingKey {
        case falsePositiveFixes = "false_positive_fixes"
        case outOfScope = "out_of_scope"
    }
}

struct AdvancedFeatures: Codable {
    let features: [AdvancedFeature]
    let reportCardChecklist: [ReportCardItem]
    enum CodingKeys: String, CodingKey {
        case features
        case reportCardChecklist = "report_card_checklist"
    }
}

struct AdvancedFeature: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let what: String
    let how: String
    let when: String
}

struct ReportCardItem: Codable, Hashable {
    let item: String
    let checks: String
}
