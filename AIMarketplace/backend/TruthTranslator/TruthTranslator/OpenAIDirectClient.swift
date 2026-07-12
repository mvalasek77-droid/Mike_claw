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
            messages: [.init(role: "user", content: ChadDropDecodePrompt.build(text: text, tone: tone, context: context))],
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
        return try ChadDropDecodePrompt.parse(content)
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

        var errorDescription: String? {
            switch self {
            case .badResponse: return "OpenAI returned an error. Check that your API key is valid."
            case .emptyResponse: return "OpenAI returned an empty response."
            }
        }
    }
}
