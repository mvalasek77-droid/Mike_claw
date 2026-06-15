import Foundation

/// Catalogue of LLM providers + models CodeGenie can route through.
///
/// Pricing is per million tokens, USD, sourced from each vendor's public
/// rate card. Update this file when models change — every cost-display
/// surface in the app reads from here so prices never drift between
/// screens.
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case anthropic
    case openai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai:    "OpenAI"
        }
    }

    var consoleURL: URL {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai:    URL(string: "https://platform.openai.com/api-keys")!
        }
    }

    var keyEnvVar: String {
        switch self {
        case .anthropic: "ANTHROPIC_API_KEY"
        case .openai:    "OPENAI_API_KEY"
        }
    }
}

struct AIModel: Identifiable, Hashable, Codable {
    var id: String           // canonical model id (e.g. "claude-opus-4-8")
    var provider: AIProvider
    var displayName: String
    var tagline: String
    var inputUSDPerMTok: Double      // USD per million input tokens
    var outputUSDPerMTok: Double     // USD per million output tokens
    var contextWindow: Int           // max tokens
    var bestFor: String              // short pitch
    var tier: Tier

    enum Tier: String, Codable, CaseIterable {
        case flagship, balanced, fast
        var label: String {
            switch self {
            case .flagship: "Flagship"
            case .balanced: "Balanced"
            case .fast:     "Fast"
            }
        }
    }
}

extension AIModel {
    /// Estimate cost for one CodeGenie build, given a typical token mix.
    /// Build telemetry shows ~120k input + 40k output tokens per app.
    func estimatedBuildCostUSD(inputTokens: Int = 120_000, outputTokens: Int = 40_000) -> Double {
        let m = 1_000_000.0
        return (Double(inputTokens) / m) * inputUSDPerMTok
             + (Double(outputTokens) / m) * outputUSDPerMTok
    }
}

enum ModelCatalogue {
    /// Hand-curated. Reorder = changes the recommendation order on Settings.
    static let all: [AIModel] = [
        // — Anthropic —
        .init(
            id: "claude-fable-5", provider: .anthropic,
            displayName: "Claude Fable 5 (Currently unavailable)",
            tagline: "Anthropic's most capable model",
            inputUSDPerMTok: 10.0, outputUSDPerMTok: 50.0,
            contextWindow: 1_000_000,
            bestFor: "The hardest builds — complex apps, long autonomous runs",
            tier: .flagship
        ),
        .init(
            id: "claude-opus-4-8", provider: .anthropic,
            displayName: "Claude Opus 4.8",
            tagline: "Best Swift code, deepest reasoning",
            inputUSDPerMTok: 5.0, outputUSDPerMTok: 25.0,
            contextWindow: 1_000_000,
            bestFor: "Architecture, hard refactors, gnarly bugs",
            tier: .flagship
        ),
        .init(
            id: "claude-sonnet-4-6", provider: .anthropic,
            displayName: "Claude Sonnet 4.6",
            tagline: "The everyday workhorse",
            inputUSDPerMTok: 3.0, outputUSDPerMTok: 15.0,
            contextWindow: 200_000,
            bestFor: "Most builds — great quality at 5× the speed of Opus",
            tier: .balanced
        ),
        .init(
            id: "claude-haiku-4-5", provider: .anthropic,
            displayName: "Claude Haiku 4.5",
            tagline: "Cheap, fast, surprisingly capable",
            inputUSDPerMTok: 1.0, outputUSDPerMTok: 5.0,
            contextWindow: 200_000,
            bestFor: "Tweaks, lints, copy edits, screenshots",
            tier: .fast
        ),
        // — OpenAI —
        // NOTE: gpt-5.5 pricing is a placeholder pending OpenAI's published
        // rate card — confirm before release. We mirror it in cost.py.
        .init(
            id: "gpt-5.5", provider: .openai,
            displayName: "GPT-5.5",
            tagline: "OpenAI's newest flagship — sharper reasoning",
            inputUSDPerMTok: 12.5, outputUSDPerMTok: 50.0,
            contextWindow: 400_000,
            bestFor: "Hard builds, deep review, a strong second opinion to Claude",
            tier: .flagship
        ),
        .init(
            id: "gpt-5", provider: .openai,
            displayName: "GPT-5",
            tagline: "OpenAI's flagship, sharp at design copy",
            inputUSDPerMTok: 12.5, outputUSDPerMTok: 50.0,
            contextWindow: 256_000,
            bestFor: "Naming, marketing copy, second-opinion review",
            tier: .flagship
        ),
        .init(
            id: "gpt-5-mini", provider: .openai,
            displayName: "GPT-5 mini",
            tagline: "Compact GPT-5 — half the price, most of the polish",
            inputUSDPerMTok: 0.25, outputUSDPerMTok: 2.0,
            contextWindow: 128_000,
            bestFor: "Bulk transformations, batch tasks",
            tier: .fast
        )
    ]

    static func model(id: String) -> AIModel? { all.first { $0.id == id } }

    static let recommendedDefault = "claude-sonnet-4-6"
}
