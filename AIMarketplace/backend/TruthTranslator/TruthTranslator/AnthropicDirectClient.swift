import Foundation

/// Which provider a user-supplied API key belongs to, detected from its prefix.
enum UserAPIKeyKind: Equatable {
    case anthropic
    case openAI

    static func detect(_ key: String) -> UserAPIKeyKind {
        key.hasPrefix("sk-ant-") ? .anthropic : .openAI
    }
}

/// Calls the Anthropic (Claude) API directly with the user's own API key (configured in AI Settings).
struct AnthropicDirectClient {
    let apiKey: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-sonnet-5"
    private static let apiVersion = "2023-06-01"

    func decode(text: String, tone: DecodeTone, context: DecodeContext) async throws -> DecodeResult {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(MessagesRequest(
            model: Self.model,
            max_tokens: 1024,
            messages: [.init(role: "user", content: ChadDropDecodePrompt.build(text: text, tone: tone, context: context))]
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AnthropicError.badResponse
        }

        let reply = try JSONDecoder().decode(MessagesResponse.self, from: data)
        guard let content = reply.content.first(where: { $0.type == "text" })?.text else {
            throw AnthropicError.emptyResponse
        }
        return try ChadDropDecodePrompt.parse(content)
    }

    private struct MessagesRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let max_tokens: Int
        let messages: [Message]
    }

    private struct MessagesResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
        let content: [ContentBlock]
    }

    enum AnthropicError: LocalizedError {
        case badResponse
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .badResponse: return "Anthropic returned an error. Check that your API key is valid."
            case .emptyResponse: return "Anthropic returned an empty response."
            }
        }
    }
}

/// Shared prompt and response parsing for the user-key clients, kept identical
/// to the contract the on-device and proxy engines use.
enum ChadDropDecodePrompt {
    static func build(text: String, tone: DecodeTone, context: DecodeContext) -> String {
        """
        You are ChadDrop, a fun and sharp text decoder for women figuring out what a guy really means.
        Use psychology, dating dynamics, and the dating marketplace to reveal the truth behind his words.
        Be blunt, funny, never mean. Use therapy techniques (CBT reframing, attachment theory, Gottman's principles).

        Analyze this text from a man and decode what he really means:
        "\(text)"

        Context: \(context.rawValue)
        Tone: \(tone.promptValue)

        Respond with ONLY valid JSON in this exact format:
        {
          "headline": "a funny one-liner headline",
          "translation": "what he actually means, blunt and funny",
          "psychology": "research-backed psychology explanation, cite studies",
          "receipts": ["signal1", "signal2"],
          "suggestedReplies": ["reply1", "reply2", "reply3"],
          "realityScore": 45,
          "energy": "short energy label with emoji",
          "flags": ["flag1", "flag2"]
        }
        """
    }

    static func parse(_ raw: String) throws -> DecodeResult {
        var jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonStr.hasPrefix("```") {
            jsonStr = jsonStr.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = jsonStr.data(using: .utf8) else {
            throw ParseError.invalid
        }
        do {
            return try JSONDecoder().decode(DecodeResult.self, from: data)
        } catch {
            throw ParseError.invalid
        }
    }

    enum ParseError: LocalizedError {
        case invalid

        var errorDescription: String? { "Could not parse the AI response." }
    }
}
