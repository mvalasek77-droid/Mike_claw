import Foundation
import Combine

/// Drives the AI features. In the default **on-device key** mode it calls the
/// Anthropic Messages API directly using the user's own key from the Keychain;
/// in **proxy** mode it calls a server the user hosts. No API key is ever
/// embedded in the app or stored outside the Keychain.
@MainActor
final class AIService: ObservableObject {
    @Published var configuration: AIConfiguration {
        didSet { AIConfigurationStore.save(configuration) }
    }
    /// Whether an API key is present in the Keychain (the value itself is never
    /// published or exposed).
    @Published private(set) var hasAPIKey: Bool

    private static let keyAccount = "anthropic.apiKey"
    private static let anthropicURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let anthropicVersion = "2023-06-01"

    init() {
        configuration = AIConfigurationStore.load()
        hasAPIKey = KeychainStore.get(account: AIService.keyAccount) != nil
    }

    // MARK: - Key management

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearAPIKey()
        } else {
            KeychainStore.set(trimmed, account: AIService.keyAccount)
            hasAPIKey = true
        }
    }

    func clearAPIKey() {
        KeychainStore.delete(account: AIService.keyAccount)
        hasAPIKey = false
    }

    /// True when the active mode has what it needs to make a live call.
    var isConfigured: Bool {
        switch configuration.mode {
        case .onDeviceKey: return hasAPIKey
        case .proxy: return configuration.proxyConfigured
        }
    }

    enum AIError: LocalizedError {
        case notConfigured
        case badResponse(Int, String?)
        case refused
        case empty
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Add your Anthropic API key in Settings to use AI tools."
            case .badResponse(let code, let message):
                if code == 401 { return "Your API key was rejected (401). Check it in Settings." }
                return message ?? "The AI service returned an error (HTTP \(code))."
            case .refused:
                return "The model declined this request."
            case .empty:
                return "The AI service returned no content."
            case .transport(let message):
                return message
            }
        }
    }

    // MARK: - Public API

    func run(_ tool: AITool,
             context: String,
             screenplay: Screenplay,
             focusCharacter: String? = nil) async throws -> String {
        let system = tool.systemPrompt(for: screenplay)
        let user = tool.userPrompt(context: context, screenplay: screenplay,
                                   focusCharacter: focusCharacter)

        guard isConfigured else {
            // Offline demo so the UI is explorable before a key is added.
            return Self.demoResponse(for: tool)
        }

        switch configuration.mode {
        case .onDeviceKey:
            return try await sendDirect(system: system, user: user, maxTokens: tool.maxTokens)
        case .proxy:
            return try await sendProxy(system: system, user: user, maxTokens: tool.maxTokens)
        }
    }

    // MARK: - Direct (BYOK) call

    private func sendDirect(system: String, user: String, maxTokens: Int) async throws -> String {
        guard let apiKey = KeychainStore.get(account: AIService.keyAccount), !apiKey.isEmpty else {
            throw AIError.notConfigured
        }

        var body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        // Only attach thinking/effort on models that accept them, or the call 400s.
        if configuration.supportsThinkingAndEffort {
            body["thinking"] = ["type": "adaptive"]
            body["output_config"] = ["effort": configuration.creativity.effort]
        }

        var request = URLRequest(url: AIService.anthropicURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(AIService.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse(0, nil) }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.badResponse(http.statusCode, Self.apiErrorMessage(from: data))
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        if decoded.stop_reason == "refusal" { throw AIError.refused }
        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.empty }
        return text
    }

    // MARK: - Proxy call (optional)

    private func sendProxy(system: String, user: String, maxTokens: Int) async throws -> String {
        guard let url = URL(string: configuration.proxyURL.trimmingTrailingSlash() + "/generate") else {
            throw AIError.notConfigured
        }
        let payload: [String: Any] = [
            "model": configuration.model,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "max_tokens": maxTokens,
            "effort": configuration.creativity.effort
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 120

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse(0, nil) }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.badResponse(http.statusCode, Self.apiErrorMessage(from: data))
        }
        struct ProxyResponse: Decodable { let text: String }
        let decoded = try JSONDecoder().decode(ProxyResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.empty }
        return text
    }

    // MARK: - Helpers

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.transport(error.localizedDescription)
        }
    }

    /// Anthropic error bodies look like `{"error": {"message": "..."}}`.
    private struct AnthropicResponse: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
        let stop_reason: String?
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable { struct E: Decodable { let message: String }; let error: E }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
    }

    // MARK: - Demo fallback

    private static func demoResponse(for tool: AITool) -> String {
        switch tool {
        case .generateLogline:
            return """
            (Sample — add your Anthropic API key in Settings for live results)

            1. A washed-up storm chaser must outrun the very tornado that killed \
            her sister to save the small town that blames her for it.
            2. When a deaf teenager films a crime no one else heard, she becomes \
            the only witness a corrupt town wants silenced.
            3. A retired safecracker is pulled into one last job — guarding the \
            vault he spent thirty years learning to break.
            """
        case .coverageNotes:
            return """
            (Sample coverage — add your API key in Settings for a real read)

            LOGLINE: A promising hook with clear stakes and an active protagonist.

            STRENGTHS
            • Strong opening image; we understand the world fast.
            • Distinct protagonist voice in the first ten pages.

            CONCERNS
            • The midpoint reversal arrives late; tension dips around p.45.
            • The antagonist's goal is implied but never stated on the page.

            NEXT STEPS
            1. Land the inciting incident before page 12.
            2. Give the antagonist one scene that states their want.
            3. Cut two of the three café scenes — they repeat the same beat.
            """
        default:
            return """
            (Sample response — add your Anthropic API key in Settings to use \
            "\(tool.title)" with live AI.)

            This is placeholder text demonstrating where \(tool.title.lowercased()) \
            output appears. Once your key is set, Sceneflow sends the relevant \
            scene or script to Claude and shows a real result here.
            """
        }
    }
}

private extension String {
    func trimmingTrailingSlash() -> String {
        var s = self
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
