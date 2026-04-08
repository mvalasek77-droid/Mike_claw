import Foundation

// MARK: - LLM Provider

/// Which backend is being used for this session.
enum LLMProvider {
    case appleFoundationModels   // on-device, iOS 26+, no privacy policy needed
    case claudeAPI               // remote Anthropic API, requires user consent
    case none                    // no provider available / consent not given
}

// MARK: - LLM Request / Response

struct LLMRequest {
    let systemPrompt: String
    let messages: [LLMMessage]
    let tools: [ToolDefinition]
    let maxTokens: Int
    let role: AgentRole
}

struct LLMMessage {
    enum Role { case user, assistant, system }
    let role: Role
    let content: String
}

struct LLMResponse {
    let content: String
    let promptTokens: Int
    let completionTokens: Int
    let provider: LLMProvider
    let toolCallsRequested: [String]   // tool IDs the model wants to invoke
}

// MARK: - Streaming handler

typealias StreamHandler = @Sendable (String) -> Void

// MARK: - HermesLLMClient

/// Single entry point for all LLM calls.
/// Automatically routes to Apple Foundation Models or Claude API based on
/// device capability and user consent.  Either way, Hermes context is
/// injected into every request before it leaves this class.
actor HermesLLMClient {
    static let shared = HermesLLMClient()

    private let memory      = HermesMemory.shared
    private let context     = HermesContextTracker.shared
    private let session     = HermesSessionState.shared
    private let privacy     = HermesPrivacyGate.shared

    private var _provider: LLMProvider = .none

    private init() {}

    // MARK: - Provider selection

    /// Call once at app start (after privacy gate resolves).
    ///
    /// Auto-bootstrap rule: if a Claude API key already exists in the Keychain
    /// we treat that as implicit cloud consent — the user put it there, so they
    /// agree data reaches Anthropic's servers.  This handles:
    ///   • First run immediately after onboarding (consent + key set together)
    ///   • Subsequent launches where consent state and key state drifted
    ///   • Key entered in Settings after skipping the provider step
    func configure() async {
        if !await privacy.consentGiven && ClaudeAPIBridge.isConfigured {
            await privacy.acceptCloudAI()
        }
        if await privacy.consentGiven {
            _provider = Self.bestAvailableProvider()
        } else {
            _provider = .none
        }
    }

    var provider: LLMProvider { _provider }

    private static func bestAvailableProvider() -> LLMProvider {
        // iOS 26+ with Apple Intelligence available → prefer on-device
        if #available(iOS 26.0, *) {
            if AppleFoundationModelsBridge.isAvailable {
                return .appleFoundationModels
            }
        }
        // Fall back to Claude API (requires API key configured)
        if ClaudeAPIBridge.isConfigured {
            return .claudeAPI
        }
        return .none
    }

    // MARK: - Main call (with full Hermes context injection)

    /// Complete an LLM turn.  Hermes memory and session context are
    /// automatically injected into the system prompt before sending.
    func complete(request: LLMRequest,
                  stream: StreamHandler? = nil) async throws -> LLMResponse {
        guard _provider != .none else {
            throw LLMError.noProviderConfigured
        }

        // Pre-turn budget check
        try await session.checkBudget(estimatedCost: request.maxTokens)

        // Build Hermes-enriched system prompt
        let enrichedSystem = await buildSystemPrompt(base: request.systemPrompt,
                                                     role: request.role)

        let enrichedRequest = LLMRequest(
            systemPrompt: enrichedSystem,
            messages: request.messages,
            tools: request.tools,
            maxTokens: request.maxTokens,
            role: request.role
        )

        // Route to provider
        let response: LLMResponse
        switch _provider {
        case .appleFoundationModels:
            response = try await AppleFoundationModelsBridge.complete(enrichedRequest, stream: stream)
        case .claudeAPI:
            response = try await ClaudeAPIBridge.complete(enrichedRequest, stream: stream)
        case .none:
            throw LLMError.noProviderConfigured
        }

        // Record token usage (strict write discipline: only on success)
        try await session.recordTokenUsage(prompt: response.promptTokens,
                                           completion: response.completionTokens)
        return response
    }

    // MARK: - Hermes context injection

    /// Builds the system prompt enriched with:
    ///   • Role-specific instructions
    ///   • Current session topic and intent
    ///   • Relevant memories from the index
    ///   • Recent dream insights
    ///   • Self-improvement notes
    private func buildSystemPrompt(base: String, role: AgentRole) async -> String {
        var sections: [String] = []

        // 1. Base instructions + role constraints
        sections.append(base)
        sections.append(roleInstructions(role))

        // 2. Current session context (lightweight — from ContextTracker, no disk read)
        if let topic = await context.currentTopic() {
            sections.append("## Current topic\n\(topic)")
        }
        if let intent = await context.currentIntent() {
            sections.append("## Detected intent\n\(intent.rawValue)")
        }
        let summary = await context.sessionSummary()
        if summary != "No activity yet." {
            sections.append("## Recent conversation\n\(summary)")
        }

        // 3. Relevant long-term memories (via MemoryIndex — no full deserialisation)
        if let topic = await context.currentTopic() {
            let keywords = topic.components(separatedBy: ", ")
            let relevant = await memory.indexSearch(keywords: keywords, limit: 5)
            if !relevant.isEmpty {
                let bullets = relevant.compactMap { entry -> String? in
                    guard let text = (entry.content.value as? [String: Any])
                        .flatMap({ $0.values.compactMap { $0 as? String }.first })
                        ?? (entry.content.value as? String)
                    else { return nil }
                    return "• [\(entry.category)] \(text.prefix(200))"
                }.joined(separator: "\n")
                sections.append("## Relevant memory\n\(bullets)")
            }
        }

        // 4. Recent dream insights (from last 24 h)
        let insights = await memory.entries(for: "dream_insight")
            .prefix(2)
            .compactMap { ($0.content.value as? [String: Any])?["insight"] as? String }
        if !insights.isEmpty {
            sections.append("## Recent insights\n" + insights.map { "• \($0)" }.joined(separator: "\n"))
        }

        // 5. Self-improvement notes
        let improvements = await memory.entries(for: "self_improvement")
            .prefix(1)
            .compactMap { ($0.content.value as? [String: Any])?["note"] as? String }
        if !improvements.isEmpty {
            sections.append("## Known issues to avoid\n" + improvements.map { "• \($0)" }.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    private func roleInstructions(_ role: AgentRole) -> String {
        switch role {
        case .explore:
            return "## Role: Explorer\nRead and investigate only. Do NOT modify any state. Summarise findings clearly and concisely."
        case .plan:
            return "## Role: Planner\nSynthesise the explorer's findings into a clear, numbered action plan. No side effects."
        case .execute:
            return "## Role: Executor\nCarry out the plan step by step. Confirm each step before moving to the next. Report success or failure explicitly."
        case .verify:
            return "## Role: Verifier\nCritically review the executor's output. Flag any discrepancies, incomplete steps, or potential issues. Be thorough."
        }
    }
}

// MARK: - Error

enum LLMError: Error, LocalizedError {
    case noProviderConfigured
    case consentNotGiven
    case apiKeyMissing
    case rateLimited
    case contextTooLong

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured: return "No AI provider configured. Please check Settings."
        case .consentNotGiven:      return "AI features require your consent. See Settings → Privacy."
        case .apiKeyMissing:        return "Claude API key not set. Add it in Settings."
        case .rateLimited:          return "Too many requests. Please wait a moment."
        case .contextTooLong:       return "Conversation too long. Starting a new session."
        }
    }
}

// MARK: - Apple Foundation Models bridge (iOS 26+)
//
// Requires:
//   1. Xcode with iOS 26 SDK (Xcode 26 beta or later)
//   2. Add FoundationModels.framework to target → Frameworks, Libraries,
//      and Embedded Content (it ships with the iOS 26 SDK, no entitlement needed)
//   3. Deployment target can stay at iOS 17+ — all API calls are guarded
//      with #available(iOS 26.0, *) at runtime

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleFoundationModelsBridge {

    // MARK: - Availability

    /// True when Apple Intelligence is supported AND enabled on this device.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:   return true
            case .unavailable: return false   // .deviceNotEligible / .appleIntelligenceNotEnabled / .modelNotReady
            }
        }
        #endif
        return false
    }

    // MARK: - Completion

    static func complete(_ request: LLMRequest,
                         stream: StreamHandler?) async throws -> LLMResponse {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try await _complete26(request, stream: stream)
        }
        #endif
        throw LLMError.noProviderConfigured
    }

    // MARK: - iOS 26 implementation (compiled only when SDK available)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func _complete26(_ request: LLMRequest,
                                    stream: StreamHandler?) async throws -> LLMResponse {
        guard case .available = SystemLanguageModel.default.availability else {
            throw LLMError.noProviderConfigured
        }

        // One session per agent run — holds conversation state internally.
        let session = LanguageModelSession(instructions: request.systemPrompt)
        let composed = composePrompt(from: request.messages)

        var fullText = ""
        let estimatedPromptTokens = composed.count / 4

        if let handler = stream {
            for try await partial in session.streamResponse(to: composed) {
                handler(partial.content)
                fullText += partial.content
            }
        } else {
            let response = try await session.respond(to: composed)
            fullText = response.content
        }

        return LLMResponse(
            content: fullText,
            promptTokens: estimatedPromptTokens,
            completionTokens: fullText.count / 4,
            provider: .appleFoundationModels,
            toolCallsRequested: []
        )
    }

    private static func composePrompt(from messages: [LLMMessage]) -> String {
        messages
            .filter { $0.role != .system }
            .map { msg -> String in
                switch msg.role {
                case .user:      return "User: \(msg.content)"
                case .assistant: return "Assistant: \(msg.content)"
                case .system:    return ""
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
    #endif
}

// MARK: - Claude API bridge

/// Calls the Anthropic Messages API.
/// Requires ANTHROPIC_API_KEY in the keychain (never in source or Info.plist).
enum ClaudeAPIBridge {

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    static var isConfigured: Bool {
        apiKey != nil
    }

    private static var apiKey: String? {
        // Read from Keychain — never hardcode
        KeychainHelper.read(service: "com.openclaw.appclaw", key: "anthropic_api_key")
    }

    static func complete(_ request: LLMRequest,
                         stream: StreamHandler?) async throws -> LLMResponse {
        guard let key = apiKey else { throw LLMError.apiKeyMissing }

        // Select model per agent role
        let model = modelForRole(request.role)

        // Build Anthropic messages array from transcript
        let messages: [[String: Any]] = request.messages.compactMap { msg in
            guard msg.role != .system else { return nil }  // system goes in top-level key
            return ["role": msg.role == .user ? "user" : "assistant",
                    "content": msg.content]
        }

        // Build tools array from ToolDefinitions
        let tools: [[String: Any]] = request.tools.map { tool in
            [
                "name":        tool.id.replacingOccurrences(of: ".", with: "_"),
                "description": tool.description,
                "input_schema": ["type": "object", "properties": tool.inputSchema]
            ]
        }

        var body: [String: Any] = [
            "model":      model,
            "max_tokens": request.maxTokens,
            "system":     request.systemPrompt,
            "messages":   messages,
        ]
        if !tools.isEmpty { body["tools"] = tools }
        if stream != nil  { body["stream"] = true }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(key,                 forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion,          forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        if let handler = stream {
            return try await streamResponse(urlRequest, handler: handler)
        } else {
            return try await blockingResponse(urlRequest)
        }
    }

    // MARK: Streaming

    private static func streamResponse(_ request: URLRequest,
                                       handler: @escaping StreamHandler) async throws -> LLMResponse {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validateHTTP(response)

        var fullText = ""
        var inputTokens = 0
        var outputTokens = 0

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard jsonStr != "[DONE]",
                  let data = jsonStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // Text delta
            if let delta = (event["delta"] as? [String: Any])?["text"] as? String {
                handler(delta)
                fullText += delta
            }
            // Usage (arrives in message_delta event)
            if let usage = event["usage"] as? [String: Any] {
                inputTokens  = usage["input_tokens"]  as? Int ?? inputTokens
                outputTokens = usage["output_tokens"] as? Int ?? outputTokens
            }
        }

        return LLMResponse(content: fullText, promptTokens: inputTokens,
                           completionTokens: outputTokens,
                           provider: .claudeAPI, toolCallsRequested: [])
    }

    // MARK: Blocking

    private static func blockingResponse(_ request: URLRequest) async throws -> LLMResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String
        else { throw LLMError.noProviderConfigured }

        let usage = json["usage"] as? [String: Any]
        let input  = usage?["input_tokens"]  as? Int ?? 0
        let output = usage?["output_tokens"] as? Int ?? 0

        // Extract any tool_use blocks
        let toolCalls = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "tool_use" }
            .compactMap { $0["name"] as? String }

        return LLMResponse(content: text, promptTokens: input,
                           completionTokens: output,
                           provider: .claudeAPI, toolCallsRequested: toolCalls)
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 429: throw LLMError.rateLimited
        default: throw LLMError.noProviderConfigured
        }
    }

    private static func modelForRole(_ role: AgentRole) -> String {
        switch role {
        case .explore:  return "claude-haiku-4-5-20251001"    // fast + cheap for reads
        case .plan:     return "claude-sonnet-4-6"            // balanced
        case .execute:  return "claude-sonnet-4-6"            // reliable for writes
        case .verify:   return "claude-opus-4-6"              // highest scrutiny
        }
    }
}

// MARK: - Keychain helper

enum KeychainHelper {
    static func read(service: String, key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    static func write(service: String, key: String, value: String) {
        let data = value.data(using: .utf8)!
        // Delete existing first
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        // Add new
        let addQuery: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      key,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
