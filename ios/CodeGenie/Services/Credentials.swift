import Foundation
import Security

/// Keychain-backed store for API keys and the chosen auth mode.
///
/// We never log keys, never write them to UserDefaults, and never round-
/// trip them through the backend in plain text. The Settings screen is
/// the only consumer — every other surface reads via `Credentials.shared`.
@MainActor
final class Credentials: ObservableObject {
    static let shared = Credentials()

    @Published private(set) var anthropicKey: String = ""
    @Published private(set) var openaiKey: String = ""
    @Published var authMode: AuthMode = .byok
    @Published var preferredModelID: String = ModelCatalogue.recommendedDefault
    @Published var backendURL: String = "https://api.codegenie.app"
    @Published private(set) var backendToken: String = ""
    /// Per-agent model overrides keyed by `AgentRole.rawValue` ("coder", "reviewer", …).
    @Published var agentModels: [String: String] = [:]
    /// Optional per-build USD cap. `nil` disables enforcement.
    @Published var costCapUSD: Double?
    /// Apple Developer Program credentials.
    @Published var appleTeamID: String = ""
    @Published var ascKeyID: String = ""
    @Published var ascIssuerID: String = ""
    @Published private(set) var ascP8PEM: String = ""
    @Published private(set) var appSpecificPassword: String = ""

    enum AuthMode: String, CaseIterable, Identifiable, Codable {
        case byok          // Bring your own API key
        case subscription  // Use Claude Pro / ChatGPT Plus session
        case codegenie     // CodeGenie-hosted (we eat the cost on a quota)

        var id: String { rawValue }
        var label: String {
            switch self {
            case .byok:         "API key"
            case .subscription: "Subscription"
            case .codegenie:    "CodeGenie hosted"
            }
        }
        var blurb: String {
            switch self {
            case .byok:
                "Paste your own Anthropic / OpenAI key. CodeGenie never sees the bill — you pay providers directly. Best price."
            case .subscription:
                "Sign into Claude Pro / Max or ChatGPT Plus on your Mac and we'll route through your existing subscription. No per-token cost."
            case .codegenie:
                "Use our hosted credits. 3 builds free, then $9.99/mo for unlimited Sonnet builds + 20 Opus builds."
            }
        }
    }

    private init() {
        anthropicKey = read(.anthropic) ?? ""
        openaiKey    = read(.openai) ?? ""
        backendToken = readBackendToken() ?? ""
        if let raw = UserDefaults.standard.string(forKey: "auth.mode"),
           let mode = AuthMode(rawValue: raw) { authMode = mode }
        if let id = UserDefaults.standard.string(forKey: "model.preferred") {
            preferredModelID = id
        }
        if let url = UserDefaults.standard.string(forKey: "backend.url"),
           !url.isEmpty {
            backendURL = url
        }
        if let data = UserDefaults.standard.data(forKey: "agent.models"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            agentModels = decoded
        }
        if UserDefaults.standard.object(forKey: "cost.cap.usd") != nil {
            let raw = UserDefaults.standard.double(forKey: "cost.cap.usd")
            costCapUSD = raw > 0 ? raw : nil
        }
        appleTeamID  = UserDefaults.standard.string(forKey: "apple.teamID") ?? ""
        ascKeyID     = UserDefaults.standard.string(forKey: "apple.ascKeyID") ?? ""
        ascIssuerID  = UserDefaults.standard.string(forKey: "apple.ascIssuer") ?? ""
        ascP8PEM     = readAppleSecret(account: "asc.p8") ?? ""
        appSpecificPassword = readAppleSecret(account: "apple.appSpecific") ?? ""
    }

    func setAppleTeamID(_ id: String) {
        appleTeamID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(appleTeamID, forKey: "apple.teamID")
    }

    func setASCKeyID(_ id: String) {
        ascKeyID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(ascKeyID, forKey: "apple.ascKeyID")
    }

    func setASCIssuerID(_ id: String) {
        ascIssuerID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(ascIssuerID, forKey: "apple.ascIssuer")
    }

    func setASCP8(_ pem: String) {
        let clean = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        ascP8PEM = clean
        writeAppleSecret(clean, account: "asc.p8")
    }

    func setAppSpecificPassword(_ pwd: String) {
        let clean = pwd.trimmingCharacters(in: .whitespacesAndNewlines)
        appSpecificPassword = clean
        writeAppleSecret(clean, account: "apple.appSpecific")
    }

    var hasAppleDevCreds: Bool {
        !appleTeamID.isEmpty
            && ((!ascKeyID.isEmpty && !ascIssuerID.isEmpty && !ascP8PEM.isEmpty)
                || !appSpecificPassword.isEmpty)
    }

    func setAgentModel(role: String, model: String?) {
        if let model { agentModels[role] = model } else { agentModels.removeValue(forKey: role) }
        if let data = try? JSONEncoder().encode(agentModels) {
            UserDefaults.standard.set(data, forKey: "agent.models")
        }
    }

    func setCostCap(_ usd: Double?) {
        costCapUSD = usd
        if let usd, usd > 0 {
            UserDefaults.standard.set(usd, forKey: "cost.cap.usd")
        } else {
            UserDefaults.standard.removeObject(forKey: "cost.cap.usd")
        }
    }

    func setBackendURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        backendURL = trimmed
        UserDefaults.standard.set(trimmed, forKey: "backend.url")
    }

    func setBackendToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        backendToken = trimmed
        writeBackendToken(trimmed)
    }

    func setKey(_ key: String, for provider: AIProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        write(trimmed, for: provider)
        switch provider {
        case .anthropic: anthropicKey = trimmed
        case .openai:    openaiKey = trimmed
        }
    }

    func clearKey(for provider: AIProvider) { setKey("", for: provider) }

    func setAuthMode(_ mode: AuthMode) {
        authMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "auth.mode")
    }

    func setPreferredModel(_ id: String) {
        preferredModelID = id
        UserDefaults.standard.set(id, forKey: "model.preferred")
    }

    var hasAnyKey: Bool { !anthropicKey.isEmpty || !openaiKey.isEmpty }

    // MARK: - Keychain plumbing

    private func read(_ provider: AIProvider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    private func write(_ value: String, for provider: AIProvider) {
        let query = baseQuery(provider)
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func baseQuery(_ provider: AIProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.codegenie.api-keys",
            kSecAttrAccount as String: provider.rawValue,
        ]
    }

    // Backend token has its own keychain entry to avoid mixing it with provider keys.
    private func backendQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.codegenie.backend-token",
            kSecAttrAccount as String: "default",
        ]
    }

    private func readBackendToken() -> String? {
        var q = backendQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    private func writeBackendToken(_ value: String) {
        let q = backendQuery()
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func appleQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.codegenie.apple-dev",
            kSecAttrAccount as String: account,
        ]
    }

    private func readAppleSecret(account: String) -> String? {
        var q = appleQuery(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    private func writeAppleSecret(_ value: String, account: String) {
        let q = appleQuery(account: account)
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
