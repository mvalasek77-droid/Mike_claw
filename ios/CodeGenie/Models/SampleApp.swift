import Foundation

/// A bundled sample app the first-run UI offers to the user. Loaded
/// from `Resources/SampleApps.json` at launch. Demo-playable samples
/// have a matching `DemoScript-<id>.json` that the canned player
/// streams into the BuildScreen.
struct SampleApp: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let iconSystemName: String
    let tint: String
    let prompt: String
    let outcome: String
    let category: AppDescription.Category?
    let style: AppDescription.Style?
    let gradeScore: Int?
    let gradeLabel: String?
    let gradeSignals: [String]?
    let demoPlayable: Bool
    let estimatedSeconds: Int

    var description: AppDescription {
        AppDescription(
            title: title,
            prompt: prompt,
            category: category ?? .utility,
            style: style ?? .liquidGlass
        )
    }

    var instantGradeScore: Int {
        min(max(gradeScore ?? 6, 1), 10)
    }

    var instantGradeLabel: String {
        gradeLabel ?? "Needs sharper hook"
    }

    var instantGradeSignals: [String] {
        gradeSignals ?? []
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case iconSystemName = "icon_system_name"
        case tint
        case prompt
        case outcome
        case category
        case style
        case gradeScore = "grade_score"
        case gradeLabel = "grade_label"
        case gradeSignals = "grade_signals"
        case demoPlayable = "demo_playable"
        case estimatedSeconds = "estimated_seconds"
    }

    /// Decode the bundled `SampleApps.json` into an array. Returns an
    /// empty list when the resource is missing (test target, snapshot
    /// rendering, etc.) so callers don't have to special-case.
    static func loadAll() -> [SampleApp] {
        guard let url = Bundle.main.url(forResource: "SampleApps", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }
        struct Wrapper: Decodable {
            let version: Int
            let samples: [SampleApp]
        }
        return (try? JSONDecoder().decode(Wrapper.self, from: data))?.samples ?? []
    }
}
