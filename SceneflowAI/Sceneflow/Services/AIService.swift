import Foundation
import Combine

/// Talks to the backend proxy that fronts the Claude Messages API. The proxy
/// owns the API key; this client only ever sees a base URL. See
/// `AIConfiguration` and `backend/proxy.py`.
@MainActor
final class AIService: ObservableObject {
    @Published var configuration: AIConfiguration {
        didSet { AIConfigurationStore.save(configuration) }
    }

    init() {
        configuration = AIConfigurationStore.load()
    }

    enum AIError: LocalizedError {
        case notConfigured
        case badResponse(Int)
        case empty
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Connect your AI backend in Settings to use AI tools."
            case .badResponse(let code):
                return "The AI backend returned an error (HTTP \(code))."
            case .empty:
                return "The AI backend returned no content."
            case .transport(let message):
                return message
            }
        }
    }

    /// Run a tool against the given context and return the assistant's text.
    func run(_ tool: AITool,
             context: String,
             screenplay: Screenplay,
             focusCharacter: String? = nil) async throws -> String {
        let system = tool.systemPrompt(for: screenplay)
        let user = tool.userPrompt(context: context, screenplay: screenplay,
                                   focusCharacter: focusCharacter)

        guard configuration.isConfigured else {
            // Offline demo so the UI is explorable without a server. Clearly
            // labelled in the UI as a sample response.
            return Self.demoResponse(for: tool)
        }

        return try await send(system: system, user: user, maxTokens: tool.maxTokens)
    }

    // MARK: - Networking

    private struct GenerateRequest: Encodable {
        let model: String
        let system: String
        let messages: [Message]
        let max_tokens: Int
        let effort: String
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct GenerateResponse: Decodable {
        let text: String
    }

    private func send(system: String, user: String, maxTokens: Int) async throws -> String {
        guard let url = URL(string: configuration.baseURL.trimmingTrailingSlash() + "/generate") else {
            throw AIError.notConfigured
        }

        let payload = GenerateRequest(
            model: configuration.model,
            system: system,
            messages: [.init(role: "user", content: user)],
            max_tokens: maxTokens,
            effort: configuration.creativity.effort
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AIError.badResponse(0) }
            guard (200..<300).contains(http.statusCode) else {
                throw AIError.badResponse(http.statusCode)
            }
            let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
            let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AIError.empty }
            return text
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.transport(error.localizedDescription)
        }
    }

    // MARK: - Demo fallback

    private static func demoResponse(for tool: AITool) -> String {
        switch tool {
        case .generateLogline:
            return """
            (Sample — connect your AI backend in Settings for live results)

            1. A washed-up storm chaser must outrun the very tornado that killed \
            her sister to save the small town that blames her for it.
            2. When a deaf teenager films a crime no one else heard, she becomes \
            the only witness a corrupt town wants silenced.
            3. A retired safecracker is pulled into one last job — guarding the \
            vault he spent thirty years learning to break.
            """
        case .coverageNotes:
            return """
            (Sample coverage — connect your AI backend in Settings for a real read)

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
            (Sample response — connect your AI backend in Settings to use \
            "\(tool.title)" with live AI.)

            This is placeholder text demonstrating where \(tool.title.lowercased()) \
            output appears. Once your proxy URL is set, Sceneflow sends the \
            relevant scene or script to Claude and streams a real result here.
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
