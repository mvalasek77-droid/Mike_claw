import Foundation

/// Runtime configuration for the AI features.
///
/// SECURITY MODEL — two ways to connect, neither embeds a key in the app:
///
/// 1. **On-device key (BYOK, default).** The user pastes *their own* Anthropic
///    API key. It is stored only in the iOS Keychain (`KeychainStore`),
///    encrypted and device-scoped, and sent directly to api.anthropic.com over
///    TLS. The key is never in this struct, never in UserDefaults, never logged.
///    This is the right choice when you're not running a server.
///
/// 2. **Proxy (optional, advanced).** The app calls a server you host, which
///    holds the key. Use this if you distribute to many users and don't want
///    each to supply a key. See `backend/proxy.py`.
///
/// Note: with BYOK the key lives on the user's own device, so the device owner
/// can in principle read their own key — that's expected (it's theirs). What
/// matters for security is that the key is not shipped in the binary, not
/// shared between users, and not stored in plaintext. Keychain handles that.
struct AIConfiguration: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case onDeviceKey
        case proxy
        var id: String { rawValue }
        var label: String {
            switch self {
            case .onDeviceKey: return "On-device key"
            case .proxy: return "My server"
            }
        }
    }

    var mode: Mode
    /// The model to use. Defaults to Claude Opus 4.8 — Anthropic's most capable
    /// Opus-tier model and a strong default for creative writing assistance.
    var model: String
    /// Surfaced as a single "creativity" dial; maps to the API effort knob.
    var creativity: Creativity
    /// Only used in `.proxy` mode.
    var proxyURL: String

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
        var effort: String {
            switch self {
            case .grounded: return "low"
            case .balanced: return "medium"
            case .bold: return "high"
            }
        }
    }

    static let `default` = AIConfiguration(
        mode: .onDeviceKey,
        model: "claude-opus-4-8",
        creativity: .balanced,
        proxyURL: ""
    )

    /// Whether the proxy URL looks usable (proxy mode only).
    var proxyConfigured: Bool {
        guard let url = URL(string: proxyURL), url.scheme != nil, url.host != nil else { return false }
        return true
    }

    /// Adaptive thinking + effort are supported on the Opus 4.x line and Sonnet
    /// 4.6, but error on Haiku 4.5. Gate the request shape on the model so a
    /// direct call never 400s on an unsupported parameter.
    var supportsThinkingAndEffort: Bool {
        model.hasPrefix("claude-opus") || model == "claude-sonnet-4-6"
    }
}

/// Persists the non-secret parts of `AIConfiguration` in UserDefaults. The API
/// key is deliberately NOT part of this — it lives only in the Keychain.
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
