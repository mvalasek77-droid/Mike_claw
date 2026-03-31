import Foundation

// MARK: - Claude API Service
// Uses the Anthropic Messages API with streaming (text/event-stream)
// https://docs.anthropic.com/en/api/messages

actor ClaudeService {
    static let shared = ClaudeService()

    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"
    private let defaultModel = "claude-sonnet-4-6"
    private let maxTokens = 8096

    // MARK: - Streaming Send

    /// Streams a response from Claude given a conversation history and available tools.
    func streamMessage(
        messages: [Message],
        systemPrompt: String,
        tools: [ClaudeTool],
        apiKey: String,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws {
        guard !apiKey.isEmpty else { throw ClaudeError.missingAPIKey }

        let requestBody = buildRequestBody(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            stream: true
        )

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("beta=true", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (stream, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in stream { errorData.append(byte) }
            let msg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, message: msg)
        }

        // Parse SSE stream
        var buffer = ""
        for try await byte in stream {
            buffer.append(Character(UnicodeScalar(byte)))
            while let newlineRange = buffer.range(of: "\n") {
                let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                if line.hasPrefix("data: ") {
                    let jsonStr = String(line.dropFirst(6))
                    if jsonStr == "[DONE]" { continue }
                    if let event = parseSSEEvent(jsonStr) {
                        onEvent(event)
                    }
                }
            }
        }
        onEvent(.done)
    }

    // MARK: - Non-streaming (for App Intents / Shortcuts)

    func sendMessage(
        messages: [Message],
        systemPrompt: String,
        tools: [ClaudeTool],
        apiKey: String
    ) async throws -> MessagesResponse {
        guard !apiKey.isEmpty else { throw ClaudeError.missingAPIKey }

        let requestBody = buildRequestBody(
            messages: messages,
            systemPrompt: systemPrompt,
            tools: tools,
            stream: false
        )

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, message: msg)
        }

        return try JSONDecoder().decode(MessagesResponse.self, from: data)
    }

    // MARK: - Private Helpers

    private func buildRequestBody(
        messages: [Message],
        systemPrompt: String,
        tools: [ClaudeTool],
        stream: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": defaultModel,
            "max_tokens": maxTokens,
            "stream": stream,
            "messages": messages
                .filter { $0.role == .user || $0.role == .assistant }
                .map { msg -> [String: Any] in
                    ["role": msg.role.rawValue, "content": msg.content]
                }
        ]

        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                var schema: [String: Any] = ["type": tool.input_schema.type]
                if let props = tool.input_schema.properties {
                    schema["properties"] = props.mapValues { p -> [String: Any] in
                        var d: [String: Any] = ["type": p.type]
                        if let desc = p.description { d["description"] = desc }
                        if let enumVals = p.enum_values { d["enum"] = enumVals }
                        return d
                    }
                }
                if let req = tool.input_schema.required { schema["required"] = req }
                return [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": schema
                ]
            }
        }

        return body
    }

    private func parseSSEEvent(_ json: String) -> StreamEvent? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return nil }

        switch type {
        case "content_block_delta":
            if let delta = obj["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String {
                if deltaType == "text_delta", let text = delta["text"] as? String {
                    return .textDelta(text)
                }
                if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                    return .toolInputDelta(partial)
                }
            }
            return nil

        case "content_block_start":
            if let block = obj["content_block"] as? [String: Any],
               let blockType = block["type"] as? String,
               blockType == "tool_use" {
                let id = block["id"] as? String ?? UUID().uuidString
                let name = block["name"] as? String ?? ""
                return .toolUseStart(id: id, name: name)
            }
            return nil

        case "message_delta":
            if let delta = obj["delta"] as? [String: Any],
               let stopReason = delta["stop_reason"] as? String {
                return .stopReason(stopReason)
            }
            return nil

        case "message_stop":
            return .done

        default:
            return nil
        }
    }
}

// MARK: - Stream Events

enum StreamEvent {
    case textDelta(String)
    case toolUseStart(id: String, name: String)
    case toolInputDelta(String)
    case stopReason(String)
    case done
}

// MARK: - API Response Models

struct MessagesResponse: Codable {
    let id: String
    let type: String
    let role: String
    let content: [ContentBlock]
    let model: String
    let stop_reason: String?
    let usage: Usage
}

struct ContentBlock: Codable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: AnyCodable]?
}

struct Usage: Codable {
    let input_tokens: Int
    let output_tokens: Int
}

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case toolExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is missing. Add your Anthropic API key in Settings."
        case .invalidResponse:
            return "Received an invalid response from the API."
        case .apiError(let code, let msg):
            return "API error \(code): \(msg)"
        case .toolExecutionFailed(let reason):
            return "Tool execution failed: \(reason)"
        }
    }
}
