import Foundation

/// Runtime configuration for the AI features.
///
/// IMPORTANT — the API key never lives in the app. A shipping iOS app cannot
/// safely embed an Anthropic key (it would be extractable from the binary and
/// could be abused at your expense). Instead the app talks to a thin backend
/// proxy you control, which holds the key and forwards requests to the
/// Messages API. See `backend/proxy.py` in this project for a reference
/// implementation. `baseURL` points at that proxy.
struct AIConfiguration: Codable, Equatable {
    /// The proxy base URL (your server). The app POSTs to `\(baseURL)/generate`.
    var baseURL: String
    /// The model the proxy should use. Defaults to Claude Opus 4.8 — Anthropic's
    /// most capable Opus-tier model, a strong default for creative writing
    /// assistance. The proxy may override or pin this.
    var model: String
    /// Higher = more creative variance, lower = tighter/safer. We surface this
    /// as a single "creativity" dial in Settings rather than raw effort.
    var creativity: Creativity

    enum Creativity: String, Codable, CaseIterable, Identifiable {
        case grounded, balanced, bold
        var id: String { rawValue }
        var label: String {
            switch self {
            case .grounded: return "Grounded"
            case .balanced: return "Balanced"
            case .bold: return "Bold"
            }
        }
        /// Maps to the API `effort` knob the proxy applies.
        var effort: String {
            switch self {
            case .grounded: return "low"
            case .balanced: return "medium"
            case .bold: return "high"
            }
        }
    }

    static let `default` = AIConfiguration(
        baseURL: "https://your-sceneflow-proxy.example.com",
        model: "claude-opus-4-8",
        creativity: .balanced
    )

    var isConfigured: Bool {
        guard let url = URL(string: baseURL), url.scheme != nil, url.host != nil else { return false }
        return !baseURL.contains("your-sceneflow-proxy.example.com")
    }
}

/// Persists `AIConfiguration` in UserDefaults.
enum AIConfigurationStore {
    private static let key = "ai.configuration"

    static func load() -> AIConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let config = try? JSONDecoder().decode(AIConfiguration.self, from: data)
        else { return .default }
        return config
    }

    static func save(_ config: AIConfiguration) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
