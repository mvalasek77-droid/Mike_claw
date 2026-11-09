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
    var id: String           // canonical model id (e.g. "claude-opus-5-5")
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
            id: "claude-opus-5-5", provider: .anthropic,
            displayName: "Claude Opus 5.5",
            tagline: "Best Swift code, deepest reasoning",
            inputUSDPerMTok: 4.0, outputUSDPerMTok: 20.0,
            contextWindow: 1_000_000,
            bestFor: "Architecture, hard refactors, gnarly bugs",
            tier: .flagship
        ),
        .init(
            id: "claude-sonnet-5-5", provider: .anthropic,
            displayName: "Claude Sonnet 5.5",
            tagline: "The everyday workhorse",
            inputUSDPerMTok: 2.0, outputUSDPerMTok: 10.0,
            contextWindow: 1_000_000,
            bestFor: "Most builds — strong quality at half the price of Opus",
            tier: .balanced
        ),
        .init(
            id: "claude-haiku-5-5", provider: .anthropic,
            displayName: "Claude Haiku 5.5",
            tagline: "Cheap, fast, surprisingly capable",
            inputUSDPerMTok: 0.10, outputUSDPerMTok: 0.50,
            contextWindow: 1_000_000,
            bestFor: "Tweaks, lints, copy edits, screenshots",
            tier: .fast
        ),
        // — OpenAI —
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

    /// Ids this app used to offer, mapped to what replaced them. A
    /// saved preference outlives the model it names; without this the
    /// picker shows nothing selected and cost estimates silently fall
    /// back to the first row.
    static let superseded: [String: String] = [
        "claude-opus-4-7": "claude-opus-5-5",
        "claude-opus-4-8": "claude-opus-5-5",
        "claude-opus-5": "claude-opus-5-5",
        "claude-sonnet-4-6": "claude-sonnet-5-5",
        "claude-sonnet-5": "claude-sonnet-5-5",
        "claude-haiku-4-5": "claude-haiku-5-5"
    ]

    static func currentID(for id: String) -> String { superseded[id] ?? id }

    static func model(id: String) -> AIModel? {
        let resolved = currentID(for: id)
        return all.first { $0.id == resolved }
    }

    static let recommendedDefault = "claude-sonnet-5-5"
}
