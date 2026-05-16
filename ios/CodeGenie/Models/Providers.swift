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

    var subscriptionURL: URL {
        switch self {
        case .anthropic: URL(string: "https://www.anthropic.com/pricing")!
        case .openai:    URL(string: "https://chatgpt.com/#pricing")!
        }
    }

    var subscriptionName: String {
        switch self {
        case .anthropic: "Claude Pro / Max"
        case .openai:    "ChatGPT Plus / Pro"
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
    var id: String           // canonical model id (e.g. "claude-opus-4-7")
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
            id: "claude-opus-4-7", provider: .anthropic,
            displayName: "Claude Opus 4.7",
            tagline: "Best Swift code, deepest reasoning",
            inputUSDPerMTok: 5.0, outputUSDPerMTok: 25.0,
            contextWindow: 200_000,
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
        .init(
            id: "gpt-5.5", provider: .openai,
            displayName: "GPT-5.5",
            tagline: "OpenAI flagship for hard product work",
            inputUSDPerMTok: 5.0, outputUSDPerMTok: 30.0,
            contextWindow: 256_000,
            bestFor: "Deep review, planning, launch copy",
            tier: .flagship
        ),
        .init(
            id: "gpt-5.4", provider: .openai,
            displayName: "GPT-5.4",
            tagline: "Balanced OpenAI coding model",
            inputUSDPerMTok: 2.5, outputUSDPerMTok: 15.0,
            contextWindow: 256_000,
            bestFor: "Design polish, second-opinion review",
            tier: .balanced
        ),
        .init(
            id: "gpt-5.4-mini", provider: .openai,
            displayName: "GPT-5.4 mini",
            tagline: "Fast OpenAI routing for bulk tasks",
            inputUSDPerMTok: 0.75, outputUSDPerMTok: 4.5,
            contextWindow: 128_000,
            bestFor: "Bulk transformations, batch tasks",
            tier: .fast
        )
    ]

    static func model(id: String) -> AIModel? { all.first { $0.id == id } }

    static let recommendedDefault = "claude-sonnet-4-6"
}
