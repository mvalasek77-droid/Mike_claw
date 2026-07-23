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

    enum CodingKeys: String, CodingKey {
        case name, id, accent, oneLiner = "one_liner", temperament, strengths
        case priceInPerMtok = "price_in_per_mtok"
        case priceOutPerMtok = "price_out_per_mtok"
        case priceNote = "price_note"
        case defaultEffort = "default_effort"
        case bestFit = "best_fit"
    }

    var priceLabel: String { "$\(fmt(priceInPerMtok)) / $\(fmt(priceOutPerMtok)) per M" }
    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
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
