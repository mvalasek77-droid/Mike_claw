import Foundation
import Security

struct DecodeService {
    private let engine = DecodeEngine()
    private let proxy = AIProxyClient()
    private let userAPI = UserAnthropicClient()

    func decode(text: String, tone: DecodeTone, context: DecodeContext) async -> DecodeOutcome {
        if userAPI.isConfigured {
            do {
                let result = try await userAPI.decode(text: text, tone: tone, context: context)
                return DecodeOutcome(
                    result: result.normalized,
                    usedFallback: false,
                    statusMessage: "Claude read complete using your saved API key."
                )
            } catch {
                let result = engine.decode(text: text, tone: tone, context: context)
                return DecodeOutcome(
                    result: result,
                    usedFallback: true,
                    statusMessage: "Saved API key could not reach Claude. Offline mode used; check the key in settings."
                )
            }
        }

        if proxy.isConfigured {
            do {
                let result = try await proxy.decode(text: text, tone: tone, context: context)
                return DecodeOutcome(result: result.normalized, usedFallback: false)
            } catch {
                let result = engine.decode(text: text, tone: tone, context: context)
                return DecodeOutcome(result: result, usedFallback: true)
            }
        }
        return DecodeOutcome(result: engine.decode(text: text, tone: tone, context: context), usedFallback: true)
    }
}

enum ChadDropAPISettings {
    static let keychainService = "com.valasek.chaddrop.api-keys"
    static let anthropicAccount = "anthropic"
}

struct AnthropicAPIKeyStore {
    private let service = ChadDropAPISettings.keychainService
    private let account = ChadDropAPISettings.anthropicAccount

    var apiKey: String {
        readFromKeychain() ?? ""
    }

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(_ key: String) {
        writeToKeychain(value: key.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func clear() {
        deleteFromKeychain()
    }

    private func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    private func writeToKeychain(value: String) {
        deleteFromKeychain()
        guard !value.isEmpty else { return }

        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct UserAnthropicClient {
    private let keyStore = AnthropicAPIKeyStore()

    private var apiKey: String {
        keyStore.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        !apiKey.isEmpty
    }

    func decode(text: String, tone: DecodeTone, context: DecodeContext) async throws -> DecodeResult {
        let key = apiKey
        guard !key.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(AnthropicRequest(
            model: "claude-sonnet-4-20250514",
            max_tokens: 900,
            system: Self.systemPrompt,
            messages: [
                AnthropicRequest.Message(
                    role: "user",
                    content: """
                    Context: \(context.rawValue)
                    Tone: \(tone.promptValue)

                    Decode this message:
                    \(text)
                    """
                )
            ]
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let textOutput = apiResponse.content.compactMap(\.text).joined(separator: "\n")
        return try Self.decodeResult(from: textOutput)
    }

    private static let systemPrompt = """
    You are ChadDrop, a sharp but safety-conscious text-message decoder.
    Keep the existing ChadDrop style: group-chat clear, witty, direct, not cruel.
    Explain what the pasted message likely means, the psychology behind it, and useful replies.
    If the message contains threats, stalking, coercion, self-harm, or physical danger, prioritize safety and do not joke.

    Return ONLY valid JSON matching this exact shape:
    {
      "headline": "short punchy verdict",
      "translation": "what the message likely means",
      "psychology": "why this pattern reads this way",
      "receipts": ["short evidence label", "another"],
      "suggestedReplies": ["reply 1", "reply 2", "reply 3"],
      "realityScore": 50,
      "energy": "short vibe label",
      "flags": ["short warning label"]
    }
    """

    private static func decodeResult(from text: String) throws -> DecodeResult {
        let cleaned = stripMarkdownFences(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return try JSONDecoder().decode(DecodeResult.self, from: data)
    }

    private static func stripMarkdownFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
            }
            if let closingRange = trimmed.range(of: "```") {
                trimmed = String(trimmed[..<closingRange.lowerBound])
            }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let firstBrace = trimmed.firstIndex(of: "{"),
              let lastBrace = trimmed.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            return trimmed
        }
        return String(trimmed[firstBrace...lastBrace])
    }

    private struct AnthropicRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct AnthropicResponse: Decodable {
        let content: [ContentBlock]

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
    }
}

struct AIProxyClient {
    private var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "AI_PROXY_URL") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    var isConfigured: Bool {
        endpoint != nil
    }

    func decode(text: String, tone: DecodeTone, context: DecodeContext) async throws -> DecodeResult {
        guard let endpoint else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ProxyRequest(
            text: text,
            tone: tone.promptValue,
            context: context.rawValue
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DecodeResult.self, from: data)
    }

    private struct ProxyRequest: Encodable {
        let text: String
        let tone: String
        let context: String
    }
}
