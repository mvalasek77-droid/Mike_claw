import Foundation

/// Calls the OpenAI API directly with the user's own API key (configured in AI Settings).
struct OpenAIDirectClient {
    let apiKey: String

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private static let model = "gpt-4o-mini"

    func decode(text: String, tone: DecodeTone, context: DecodeContext) async throws -> DecodeResult {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: Self.model,
            messages: [.init(role: "user", content: buildPrompt(text: text, tone: tone, context: context))],
            response_format: .init(type: "json_object")
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OpenAIError.badResponse
        }

        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chat.choices.first?.message.content else {
            throw OpenAIError.emptyResponse
        }
        return try parseResult(content)
    }

    private func buildPrompt(text: String, tone: DecodeTone, context: DecodeContext) -> String {
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

    private func parseResult(_ raw: String) throws -> DecodeResult {
        var jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonStr.hasPrefix("```") {
            jsonStr = jsonStr.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = jsonStr.data(using: .utf8) else {
            throw OpenAIError.parseError
        }
        do {
            return try JSONDecoder().decode(DecodeResult.self, from: data)
        } catch {
            throw OpenAIError.parseError
        }
    }

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct ResponseFormat: Encodable {
            let type: String
        }
        let model: String
        let messages: [Message]
        let response_format: ResponseFormat
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    enum OpenAIError: LocalizedError {
        case badResponse
        case emptyResponse
        case parseError

        var errorDescription: String? {
            switch self {
            case .badResponse: return "OpenAI returned an error. Check that your API key is valid."
            case .emptyResponse: return "OpenAI returned an empty response."
            case .parseError: return "Could not parse the OpenAI response."
            }
        }
    }
}
