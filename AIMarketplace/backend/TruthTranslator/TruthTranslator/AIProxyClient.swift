import Foundation
import Security

struct DecodeService {
    private let engine = DecodeEngine()
    private let proxy = AIProxyClient()
    private let userAPI = UserAnthropicClient()

    func decode(text: String, tone: DecodeTone, context: DecodeContext) async -> DecodeOutcome {
        var apiFailure: String?

        // Tier 1: user's own Claude key (opted-in cloud read).
        if userAPI.isConfigured {
            do {
                let result = try await userAPI.decode(text: text, tone: tone, context: context)
                return DecodeOutcome(
                    result: result.normalized,
                    usedFallback: false,
                    statusMessage: "Claude read complete using your saved API key."
                )
            } catch {
                apiFailure = Self.describe(error)
            }
        }

        // Tier 2: hosted proxy, if the build ships one.
        if proxy.isConfigured {
            do {
                let result = try await proxy.decode(text: text, tone: tone, context: context)
                return DecodeOutcome(result: result.normalized, usedFallback: false)
            } catch {
                // fall through
            }
        }

        // Tier 3: on-device Apple Intelligence (free, private) when available.
        if let onDevice = await onDeviceDecode(text: text, tone: tone, context: context) {
            return onDevice
        }

        // Tier 4: local heuristic engine.
        let local = engine.decode(text: text, tone: tone, context: context)
        if let apiFailure {
            return DecodeOutcome(
                result: local,
                usedFallback: true,
                statusMessage: "Offline mode used. \(apiFailure) Check the key in settings."
            )
        }
        return DecodeOutcome(result: local, usedFallback: true)
    }

    private func onDeviceDecode(text: String, tone: DecodeTone, context: DecodeContext) async -> DecodeOutcome? {
        if #available(iOS 26.0, *) {
            let client = AppleFoundationClient()
            guard client.isAvailable else { return nil }
            do {
                let result = try await client.decode(text: text, tone: tone, context: context)
                return DecodeOutcome(
                    result: result.normalized,
                    usedFallback: false,
                    statusMessage: "On-device Apple Intelligence read complete."
                )
            } catch {
                return nil
            }
        }
        return nil
    }

    private static func describe(_ error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return ".?!".contains(raw.last ?? " ") ? raw : raw + "."
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
    /// The Claude model used for decoding. Verified available and returning
    /// valid decode JSON for ChadDrop accounts.
    static let model = "claude-sonnet-5"

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
            model: Self.model,
            max_tokens: 900,
            system: ChadDropPrompt.system,
            messages: [
                AnthropicRequest.Message(
                    role: "user",
                    content: ChadDropPrompt.userMessage(text: text, tone: tone, context: context)
                )
            ]
        ))

        let data = try await Self.send(request)
        let apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let textOutput = apiResponse.content.compactMap(\.text).joined(separator: "\n")
        return try ChadDropPrompt.parse(textOutput)
    }

    /// Sends the request, retrying once on transient overload/rate-limit so a
    /// momentary 429/500/503/529 doesn't drop the user to offline mode.
    private static func send(_ request: URLRequest) async throws -> Data {
        let transient: Set<Int> = [408, 429, 500, 502, 503, 529]
        var attempt = 0
        while true {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if (200..<300).contains(http.statusCode) {
                return data
            }
            if transient.contains(http.statusCode), attempt < 1 {
                attempt += 1
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                continue
            }
            throw AnthropicClientError.http(status: http.statusCode, message: errorMessage(from: data))
        }
    }


    private static func errorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = obj["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    enum AnthropicClientError: LocalizedError {
        case http(status: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case let .http(status, message):
                if let message { return "Claude error \(status): \(message)" }
                return "Claude error \(status)."
            }
        }
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
