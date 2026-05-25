import SwiftUI

/// A portfolio for a single AI model/tool — a place for each AI to show off
/// what it can do, built entirely from the titles it produced on the
/// marketplace (disclosed by creators). One title can credit several models, so
/// it can appear in more than one studio.
struct AIStudio: Identifiable, Hashable {
    let name: String
    let titles: [MediaItem]

    var id: String { name }

    var titleCount: Int { titles.count }
    var totalSales: Int { titles.reduce(0) { $0 + $1.purchases } }

    var averageScore: Int {
        guard !titles.isEmpty else { return 0 }
        return Int((Double(titles.map(\.commercialScore).reduce(0, +)) / Double(titles.count)).rounded())
    }

    /// Best-reviewed title — the showreel headliner.
    var headliner: MediaItem? { titles.max { $0.commercialScore < $1.commercialScore } }

    /// Titles ordered for the showcase reel (best first).
    var showcase: [MediaItem] { titles.sorted { $0.commercialScore > $1.commercialScore } }

    var types: [MediaType] {
        MediaType.allCases.filter { type in titles.contains { $0.type == type } }
    }

    var accent: Color { types.first?.accent ?? Theme.accent }
    var tagline: String { AIStudioCatalog.tagline(for: name, types: types) }
    var capabilities: [String] { AIStudioCatalog.capabilities(for: name, types: types) }
}

/// Static knowledge about each AI model plus the logic that assembles studios
/// from the live catalogue.
enum AIStudioCatalog {

    static func build(from items: [MediaItem]) -> [AIStudio] {
        var byTool: [String: [MediaItem]] = [:]
        for item in items {
            for tool in item.aiTools {
                byTool[tool, default: []].append(item)
            }
        }
        return byTool
            .map { AIStudio(name: $0.key, titles: $0.value) }
            .sorted {
                if $0.totalSales != $1.totalSales { return $0.totalSales > $1.totalSales }
                return $0.titleCount > $1.titleCount
            }
    }

    private static let taglines: [String: String] = [
        "GPT-5": "Long-form storytelling with structural control and a literary ear.",
        "Claude Opus 4": "Character-driven prose and dialogue with a strong sense of voice.",
        "Gemini Ultra": "Sweeping, idea-dense narratives that connect the dots across a plot.",
        "Llama 4": "Open, fast drafting that nails genre conventions.",
        "Mistral Large": "Tight, efficient prose and crisp pacing.",
        "Sudowrite": "A novelist's co-pilot — scene craft, description, and momentum.",
        "Suno v4": "Full songs — vocals, hooks and arrangement — in any genre.",
        "Udio": "Studio-grade tracks with rich instrumentation and texture.",
        "Stable Audio": "Sound design and instrumental beds with precise control.",
        "ElevenLabs Music": "Expressive vocals and scoring that carry real emotion.",
        "AIVA": "Cinematic and classical composition with orchestral depth.",
        "Soundraw": "Adaptive, royalty-free tracks tuned to mood and length.",
        "Sora": "Photoreal, physically coherent video from a written scene.",
        "Runway Gen-4": "Stylized, art-directed motion with consistent characters.",
        "Google Veo": "High-fidelity cinematic shots with controllable camera moves.",
        "Kling": "Fluid, lifelike motion and complex action sequences.",
        "Pika": "Punchy, stylish short-form video and effects.",
        "Luma Dream Machine": "Dreamlike, high-motion sequences with depth and parallax."
    ]

    static func tagline(for name: String, types: [MediaType]) -> String {
        if let known = taglines[name] { return known }
        let kinds = types.map { $0.plural.lowercased() }.joined(separator: " & ")
        return "Generates commercial-grade \(kinds.isEmpty ? "media" : kinds)."
    }

    private static let capabilityMap: [String: [String]] = [
        "GPT-5": ["Multi-chapter structure", "Consistent characters", "Genre range", "Dialogue"],
        "Claude Opus 4": ["Distinct narrative voice", "Interiority", "Dialogue", "Editing"],
        "Gemini Ultra": ["World-building", "Plot architecture", "Research-rich detail"],
        "Suno v4": ["Vocals + lyrics", "Hooks", "Full arrangements", "Any genre"],
        "Udio": ["Instrumentation", "Mixing", "Texture & layering"],
        "ElevenLabs Music": ["Expressive vocals", "Scoring", "Emotional dynamics"],
        "AIVA": ["Orchestration", "Cinematic scoring", "Classical forms"],
        "Sora": ["Photoreal video", "Scene continuity", "Physical coherence"],
        "Runway Gen-4": ["Style transfer", "Character consistency", "Motion control"],
        "Google Veo": ["Cinematic shots", "Camera control", "High fidelity"],
        "Kling": ["Lifelike motion", "Action sequences", "Long shots"]
    ]

    static func capabilities(for name: String, types: [MediaType]) -> [String] {
        if let known = capabilityMap[name] { return known }
        return types.map { type in
            switch type {
            case .novel: return "Prose & narrative"
            case .music: return "Composition & audio"
            case .movie: return "Video & motion"
            }
        }
    }
}
