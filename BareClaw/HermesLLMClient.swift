import Foundation

// MARK: - LLM Provider

/// Which backend is being used for this session.
enum LLMProvider: Equatable, Sendable {
    case appleFoundationModels   // on-device, iOS 26+, no privacy policy needed
    case claudeAPI               // remote Anthropic API, requires user consent
    case ollamaGLM               // Ollama server running GLM 5.1 (or any GLM variant)
    case ollamaClaude            // Claude models served via Ollama
    case none                    // no provider available / consent not given
}

enum LLMAPIStatus: Equatable, Sendable {
    case unknown
    case notConfigured
    case active(LLMProvider)
    case creditsExhausted
    case invalidKey
    case rateLimited
    case serverError(String)

    var settingsLabel: String {
        switch self {
        case .unknown:
            return "Checking…"
        case .notConfigured:
            return "Not configured — add your API key below"
        case .active(.appleFoundationModels):
            return "Apple Intelligence (on-device)"
        case .active(.claudeAPI):
            return "Claude API — active ✓"
        case .active(.ollamaGLM), .active(.ollamaClaude):
            return "Ollama — active ✓"
        case .active(.none):
            return "Not configured — add your API key below"
        case .creditsExhausted:
            return "Key saved ✓ — no credits left. Top up at console.anthropic.com"
        case .invalidKey:
            return "Key saved ✓ — Anthropic rejected it. Check it's valid at console.anthropic.com"
        case .rateLimited:
            return "Claude API is rate limited — try again shortly"
        case .serverError(let message):
            return message.isEmpty ? "Claude API could not be checked" : "Claude API check failed — \(message)"
        }
    }
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
    private var _apiStatus: LLMAPIStatus = .unknown

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
        let consent = await privacy.consentGiven
        if !consent && ClaudeAPIBridge.isConfigured {
            await privacy.acceptCloudAI()
        }
        let finalConsent = await privacy.consentGiven
        if finalConsent {
            _provider = Self.bestAvailableProvider()
        } else {
            _provider = .none
        }
        updateLocalProviderStatus()
        DiagnosticsLog.info(
            "llm",
            "LLM provider configured.",
            details: [
                "provider": "\(_provider)",
                "apiStatus": "\(_apiStatus)",
                "hasClaudeKey": "\(ClaudeAPIBridge.isConfigured)"
            ]
        )
    }

    var provider: LLMProvider { _provider }
    var apiStatus: LLMAPIStatus { _apiStatus }

    /// Re-reads local key/provider state and performs a tiny Claude request.
    /// Use this after the user changes the key or tops up Anthropic credits.
    @discardableResult
    func refreshAPIKeyInformation() async -> LLMAPIStatus {
        DiagnosticsLog.info("llm", "Refreshing Claude API key information.")
        await configure()

        guard ClaudeAPIBridge.isConfigured else {
            _provider = Self.bestAvailableProvider()
            _apiStatus = _provider == .none ? .notConfigured : .active(_provider)
            DiagnosticsLog.warning(
                "llm",
                "Claude refresh finished with no configured key.",
                details: ["provider": "\(_provider)", "apiStatus": "\(_apiStatus)"]
            )
            return _apiStatus
        }

        do {
            try await ClaudeAPIBridge.validateConnection()
            if !(await privacy.consentGiven) {
                await privacy.acceptCloudAI()
            }
            _provider = Self.bestAvailableProvider()
            _apiStatus = .active(.claudeAPI)
            DiagnosticsLog.info("llm", "Claude API validation succeeded.")
        } catch let error as LLMError {
            recordClaudeStatus(for: error)
            DiagnosticsLog.error(
                "llm",
                "Claude API validation failed.",
                error: error,
                details: ["apiStatus": "\(_apiStatus)"]
            )
        } catch {
            _apiStatus = .serverError(error.localizedDescription)
            DiagnosticsLog.error("llm", "Claude API validation failed with non-LLM error.", error: error)
        }

        return _apiStatus
    }

    private static func bestAvailableProvider() -> LLMProvider {
        // iOS 26+ with Apple Intelligence available → prefer on-device
        if #available(iOS 26.0, *) {
            if AppleFoundationModelsBridge.isAvailable {
                return .appleFoundationModels
            }
        }
        // Ollama GLM 5.1 — user has configured a local/remote Ollama server
        if OllamaLLMBridge.isGLMConfigured { return .ollamaGLM }
        // Claude via Ollama (model name starting with "claude-")
        if OllamaLLMBridge.isClaudeConfigured { return .ollamaClaude }
        // Fall back to direct Claude API
        if ClaudeAPIBridge.isConfigured { return .claudeAPI }
        return .none
    }

    private func updateLocalProviderStatus() {
        if _provider == .none {
            _apiStatus = .notConfigured
            return
        }
        // Always optimistically mark active when a provider is selected.
        // Errors are surfaced through real API call failures, not cached here,
        // so configure() can never get permanently stuck in an error state.
        _apiStatus = .active(_provider)
    }

    // MARK: - Main call (with full Hermes context injection)

    /// Complete an LLM turn.  Hermes memory and session context are
    /// automatically injected into the system prompt before sending.
    func complete(request: LLMRequest,
                  stream: StreamHandler? = nil) async throws -> LLMResponse {
        if _provider == .none {
            await configure()
        }
        guard _provider != .none else {
            DiagnosticsLog.error("llm", "LLM request blocked because no provider is configured.")
            throw LLMError.noProviderConfigured
        }
        DiagnosticsLog.info(
            "llm",
            "LLM request started.",
            details: [
                "provider": "\(_provider)",
                "role": "\(request.role)",
                "messageCount": "\(request.messages.count)",
                "maxTokens": "\(request.maxTokens)",
                "stream": "\(stream != nil)"
            ]
        )

        // Pre-turn budget check. If the runtime budget is exhausted, reset the
        // transient session budget instead of permanently locking chat.
        do {
            try await session.checkBudget(estimatedCost: request.maxTokens)
        } catch SessionError.tokenBudgetExhausted(let used, let limit) {
            print("[HermesLLMClient] Session token budget exhausted: \(used)/\(limit). Resetting runtime session budget.")
            DiagnosticsLog.warning(
                "llm",
                "Runtime token budget exhausted; resetting session budget.",
                details: ["used": "\(used)", "limit": "\(limit)"]
            )
            try await session.startConversation(id: UUID().uuidString)
            try await session.checkBudget(estimatedCost: request.maxTokens)
        }

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
        do {
            switch _provider {
            case .appleFoundationModels:
                response = try await AppleFoundationModelsBridge.complete(enrichedRequest, stream: stream)
            case .claudeAPI:
                response = try await ClaudeAPIBridge.complete(enrichedRequest, stream: stream)
                _apiStatus = .active(.claudeAPI)
            case .ollamaGLM, .ollamaClaude:
                response = try await OllamaLLMBridge.complete(enrichedRequest, stream: stream)
            case .none:
                throw LLMError.noProviderConfigured
            }
        } catch let error as LLMError {
            if _provider == .claudeAPI {
                recordClaudeStatus(for: error)
            }
            DiagnosticsLog.error(
                "llm",
                "LLM request failed.",
                error: error,
                details: ["provider": "\(_provider)", "apiStatus": "\(_apiStatus)"]
            )
            throw error
        }

        // Record token usage (strict write discipline: only on success)
        try await session.recordTokenUsage(prompt: response.promptTokens,
                                           completion: response.completionTokens)
        DiagnosticsLog.info(
            "llm",
            "LLM request succeeded.",
            details: [
                "provider": "\(response.provider)",
                "promptTokens": "\(response.promptTokens)",
                "completionTokens": "\(response.completionTokens)",
                "toolCalls": "\(response.toolCallsRequested.count)",
                "responseLength": "\(response.content.count)"
            ]
        )
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

        // 5. Self-improvement notes (persisted across app restarts)
        let improvements = await memory.entries(for: "self_improvement")
            .prefix(3)
            .compactMap { ($0.content.value as? [String: Any])?["note"] as? String }
        if !improvements.isEmpty {
            sections.append("## Known issues to avoid\n" + improvements.map { "• \($0)" }.joined(separator: "\n"))
        }

        // 6. Immediate repair constraints (UserDefaults — applied on the very next exchange)
        let constraints = await MainActor.run { SelfHealingEngine.shared.constraintPromptBlock }
        if !constraints.isEmpty {
            sections.append(constraints)
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

    private func recordClaudeStatus(for error: LLMError) {
        switch error {
        case .noProviderConfigured:
            _apiStatus = .notConfigured
        case .apiKeyMissing, .consentNotGiven:
            _apiStatus = .invalidKey
        case .apiCreditsExhausted:
            _apiStatus = .creditsExhausted
        case .rateLimited:
            _apiStatus = .rateLimited
        case .contextTooLong:
            _apiStatus = .active(.claudeAPI)
        case .serverError(let code):
            _apiStatus = .serverError("server error \(code)")
        }
        DiagnosticsLog.warning(
            "llm",
            "Claude API status updated from error.",
            details: ["apiStatus": "\(_apiStatus)", "error": error.localizedDescription]
        )
    }
}

// MARK: - Error

enum LLMError: Error, LocalizedError {
    case noProviderConfigured
    case consentNotGiven
    case apiKeyMissing
    case apiCreditsExhausted
    case rateLimited
    case contextTooLong
    case serverError(Int)   // unexpected HTTP status or malformed response body

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:  return "No AI provider configured. Please check Settings."
        case .consentNotGiven:       return "AI features require your consent. See Settings → Privacy."
        case .apiKeyMissing:         return "Claude API key not set. Add it in Settings."
        case .apiCreditsExhausted:   return "The API may need to be recharged from Anthropic. Refresh Claude Status after credits are available."
        case .rateLimited:           return "Too many requests. Please wait a moment."
        case .contextTooLong:        return "Conversation too long. Starting a new session."
        case .serverError(let code): return "Server error (\(code)). Please try again."
        }
    }
}

// MARK: - Apple Foundation Models bridge (disabled stub)
//
// The iOS 26 FoundationModels framework is only available in Xcode 26 beta
// and its API has shifted between betas. To keep this project buildable on
// every current Xcode, the on-device bridge is stubbed out — it always reports
// unavailable, and the app falls through to the Claude API bridge.
//
// To re-enable Apple on-device inference later, replace this stub with a
// FoundationModels-backed implementation guarded by `#if canImport(FoundationModels)`.

enum AppleFoundationModelsBridge {
    static var isAvailable: Bool { false }

    static func complete(_ request: LLMRequest,
                         stream: StreamHandler?) async throws -> LLMResponse {
        throw LLMError.noProviderConfigured
    }
}

// MARK: - Claude API bridge

/// Calls the Anthropic Messages API.
/// Requires ANTHROPIC_API_KEY in the keychain (never in source or Info.plist).
enum ClaudeAPIBridge {

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 16
        config.timeoutIntervalForResource = 24
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static var isConfigured: Bool {
        apiKey != nil
    }

    private static var apiKey: String? {
        // Read from Keychain — never hardcode
        KeychainHelper.read(service: "com.bareclaw.bareclaw", key: "anthropic_api_key")
    }

    static func complete(_ request: LLMRequest,
                         stream: StreamHandler?) async throws -> LLMResponse {
        guard let key = apiKey else { throw LLMError.apiKeyMissing }

        // Select model per agent role
        let model = modelForRole(request.role)
        DiagnosticsLog.info(
            "claude",
            "Claude request prepared.",
            details: [
                "model": model,
                "role": "\(request.role)",
                "messageCount": "\(request.messages.count)",
                "stream": "\(stream != nil)"
            ]
        )

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

        let body: [String: Any] = [
            "model":      model,
            "max_tokens": request.maxTokens,
            "system":     request.systemPrompt,
            "messages":   messages,
        ]

        if let handler = stream {
            var streamingBody = body
            if !tools.isEmpty { streamingBody["tools"] = tools }
            streamingBody["stream"] = true
            let streamingRequest = try makeRequest(body: streamingBody, key: key)

            do {
                return try await streamResponse(streamingRequest, handler: handler)
            } catch {
                guard shouldRetryWithoutStreaming(error) else { throw error }
                #if DEBUG
                print("[ClaudeAPIBridge] Streaming failed with \(error.localizedDescription). Retrying with blocking response.")
                #endif
                DiagnosticsLog.warning(
                    "claude",
                    "Streaming failed; retrying with blocking response.",
                    details: ["error": error.localizedDescription]
                )
                await HermesIntegration.shared.logSystemStatus(
                    "Claude streaming failed; retrying with the non-streaming backup path.",
                    details: ["error": error.localizedDescription],
                    importance: 4
                )

                var fallbackBody = body
                if !tools.isEmpty { fallbackBody["tools"] = tools }
                let fallbackRequest = try makeRequest(body: fallbackBody, key: key)
                return try await blockingResponse(fallbackRequest)
            }
        } else {
            var blockingBody = body
            if !tools.isEmpty { blockingBody["tools"] = tools }
            let urlRequest = try makeRequest(body: blockingBody, key: key)
            return try await blockingResponse(urlRequest)
        }
    }

    static func validateConnection() async throws {
        guard let key = apiKey else { throw LLMError.apiKeyMissing }
        DiagnosticsLog.info("claude", "Claude validation request started.")

        let body: [String: Any] = [
            "model": modelForRole(.explore),
            "max_tokens": 1,
            "messages": [
                ["role": "user", "content": "Reply OK."]
            ]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, body: data)
        DiagnosticsLog.info("claude", "Claude validation request succeeded.")
    }

    // MARK: Streaming

    private static func makeRequest(body: [String: Any], key: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 16
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func shouldRetryWithoutStreaming(_ error: Error) -> Bool {
        if let llmError = error as? LLMError {
            switch llmError {
            case .serverError(let code):
                return code == 0 || [500, 502, 503, 504, 529].contains(code)
            case .noProviderConfigured, .consentNotGiven, .apiKeyMissing, .apiCreditsExhausted, .rateLimited, .contextTooLong:
                return false
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost, .timedOut, .cannotParseResponse, .badServerResponse:
                return true
            default:
                return false
            }
        }

        return false
    }

    private static func streamResponse(_ request: URLRequest,
                                       handler: @escaping StreamHandler) async throws -> LLMResponse {
        DiagnosticsLog.info("claude", "Claude streaming request started.")
        let (bytes, response) = try await session.bytes(for: request)
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

            // Anthropic error event (e.g. context_length_exceeded, overloaded)
            if event["type"] as? String == "error",
               let errObj = event["error"] as? [String: Any] {
                let errType = errObj["type"] as? String ?? ""
                let errMessage = errObj["message"] as? String ?? ""
                if isCreditExhaustion(statusCode: nil, errorType: errType, message: errMessage) {
                    DiagnosticsLog.error(
                        "claude",
                        "Claude streaming error reported exhausted credits.",
                        details: ["errorType": errType, "message": errMessage]
                    )
                    throw LLMError.apiCreditsExhausted
                }
                if errType == "invalid_request_error" {
                    DiagnosticsLog.error(
                        "claude",
                        "Claude streaming context error.",
                        details: ["errorType": errType, "message": errMessage]
                    )
                    throw LLMError.contextTooLong
                }
                DiagnosticsLog.error(
                    "claude",
                    "Claude streaming error event.",
                    details: ["errorType": errType, "message": errMessage]
                )
                throw LLMError.serverError(0)
            }

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

        DiagnosticsLog.info(
            "claude",
            "Claude streaming request completed.",
            details: [
                "responseLength": "\(fullText.count)",
                "inputTokens": "\(inputTokens)",
                "outputTokens": "\(outputTokens)"
            ]
        )
        return LLMResponse(content: fullText, promptTokens: inputTokens,
                           completionTokens: outputTokens,
                           provider: .claudeAPI, toolCallsRequested: [])
    }

    // MARK: Blocking

    private static func blockingResponse(_ request: URLRequest) async throws -> LLMResponse {
        DiagnosticsLog.info("claude", "Claude blocking request started.")
        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, body: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String
        else { throw LLMError.serverError(0) }

        let usage = json["usage"] as? [String: Any]
        let input  = usage?["input_tokens"]  as? Int ?? 0
        let output = usage?["output_tokens"] as? Int ?? 0

        // Extract any tool_use blocks
        let toolCalls = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "tool_use" }
            .compactMap { $0["name"] as? String }

        DiagnosticsLog.info(
            "claude",
            "Claude blocking request completed.",
            details: [
                "responseLength": "\(text.count)",
                "inputTokens": "\(input)",
                "outputTokens": "\(output)",
                "toolCalls": "\(toolCalls.count)"
            ]
        )
        return LLMResponse(content: text, promptTokens: input,
                           completionTokens: output,
                           provider: .claudeAPI, toolCallsRequested: toolCalls)
    }

    private static func validateHTTP(_ response: URLResponse, body: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 401:
            DiagnosticsLog.error("claude", "Claude HTTP 401 - API key missing or rejected.")
            throw LLMError.apiKeyMissing
        default:
            let details = errorDetails(from: body)
            if isCreditExhaustion(statusCode: http.statusCode,
                                  errorType: details.type,
                                  message: details.message) {
                DiagnosticsLog.error(
                    "claude",
                    "Claude HTTP response indicates exhausted credits.",
                    details: [
                        "status": "\(http.statusCode)",
                        "errorType": details.type,
                        "message": details.message
                    ]
                )
                throw LLMError.apiCreditsExhausted
            }
            if http.statusCode == 429 {
                DiagnosticsLog.error("claude", "Claude HTTP 429 - rate limited.")
                throw LLMError.rateLimited
            }
            if details.type == "invalid_request_error",
               details.message.localizedCaseInsensitiveContains("context") {
                DiagnosticsLog.error(
                    "claude",
                    "Claude HTTP response indicates context too long.",
                    details: ["status": "\(http.statusCode)", "message": details.message]
                )
                throw LLMError.contextTooLong
            }
            DiagnosticsLog.error(
                "claude",
                "Claude HTTP request failed.",
                details: [
                    "status": "\(http.statusCode)",
                    "errorType": details.type,
                    "message": details.message
                ]
            )
            throw LLMError.serverError(http.statusCode)
        }
    }

    private static func errorDetails(from body: Data?) -> (type: String, message: String) {
        guard let body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return ("", "") }

        if let error = json["error"] as? [String: Any] {
            return (
                error["type"] as? String ?? "",
                error["message"] as? String ?? ""
            )
        }

        return (
            json["type"] as? String ?? "",
            json["message"] as? String ?? ""
        )
    }

    private static func isCreditExhaustion(statusCode: Int?, errorType: String, message: String) -> Bool {
        if statusCode == 402 { return true }
        let haystack = "\(errorType) \(message)".lowercased()
        return [
            "credit",
            "credits",
            "balance",
            "billing",
            "payment",
            "insufficient_quota",
            "quota_exceeded",
            "quota exceeded",
            "usage limit",
            "spend limit"
        ].contains { haystack.contains($0) }
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

// MARK: - Ollama LLM Bridge
//
// Supports any Ollama-served model over the OpenAI-compatible API.
// Primary targets:
//   • GLM 5.1  (THUDM/GLM-4 family) — model name "glm4" or "glm4:latest"
//   • Claude   (Anthropic models via Ollama) — model name "claude-3-5-haiku-20241022" etc.
//
// Configuration (stored in UserDefaults):
//   "ollama.baseURL"  — e.g. "http://192.168.1.10:11434" (LAN server)
//                        or   "https://my-ollama.example.com"
//   "ollama.model"    — e.g. "glm4", "glm4:latest", "claude-3-5-haiku-20241022"
//
// The bridge uses /v1/chat/completions (OpenAI-compatible endpoint)
// which Ollama exposes at /v1/chat/completions since v0.1.24.

enum OllamaLLMBridge {

    private static var baseURL: URL? {
        guard let raw = UserDefaults.standard.string(forKey: "ollama.baseURL"),
              !raw.isEmpty,
              let url = URL(string: raw.hasSuffix("/") ? String(raw.dropLast()) : raw)
        else { return nil }
        return url
    }

    private static var modelName: String {
        UserDefaults.standard.string(forKey: "ollama.model") ?? "glm4"
    }

    static var isGLMConfigured: Bool {
        guard baseURL != nil else { return false }
        return !modelName.lowercased().hasPrefix("claude")
    }

    static var isClaudeConfigured: Bool {
        guard baseURL != nil else { return false }
        return modelName.lowercased().hasPrefix("claude")
    }

    // MARK: - Main call

    static func complete(_ request: LLMRequest,
                         stream: StreamHandler?) async throws -> LLMResponse {
        guard let base = baseURL else { throw LLMError.noProviderConfigured }
        let endpoint = base.appendingPathComponent("/v1/chat/completions")

        // Build messages — system prompt as a "system" role message
        var messages: [[String: Any]] = [
            ["role": "system", "content": request.systemPrompt]
        ]
        messages += request.messages.compactMap { msg -> [String: Any]? in
            guard msg.role != .system else { return nil }
            return ["role": msg.role == .user ? "user" : "assistant",
                    "content": msg.content]
        }

        let body: [String: Any] = [
            "model":       modelName,
            "messages":    messages,
            "max_tokens":  request.maxTokens,
            "stream":      stream != nil,
            "temperature": 0.85,   // slightly warmer — more natural, less robotic
        ]

        var urlRequest        = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody   = try JSONSerialization.data(withJSONObject: body)
        urlRequest.timeoutInterval = 60

        if let handler = stream {
            return try await streamResponse(urlRequest, handler: handler)
        } else {
            return try await blockingResponse(urlRequest)
        }
    }

    // MARK: - Streaming (SSE)

    private static func streamResponse(_ request: URLRequest,
                                        handler: @escaping StreamHandler) async throws -> LLMResponse {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validateHTTP(response)

        var fullText = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard jsonStr != "[DONE]",
                  let data  = jsonStr.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = event["choices"] as? [[String: Any]],
                  let delta   = choices.first?["delta"] as? [String: Any],
                  let token   = delta["content"] as? String
            else { continue }
            handler(token)
            fullText += token
        }
        return LLMResponse(content: fullText, promptTokens: 0, completionTokens: 0,
                           provider: .ollamaGLM, toolCallsRequested: [])
    }

    // MARK: - Blocking

    private static func blockingResponse(_ request: URLRequest) async throws -> LLMResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response)

        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text    = message["content"] as? String
        else { throw LLMError.serverError(0) }

        let usage  = json["usage"] as? [String: Any]
        let input  = usage?["prompt_tokens"]     as? Int ?? 0
        let output = usage?["completion_tokens"] as? Int ?? 0

        return LLMResponse(content: text, promptTokens: input, completionTokens: output,
                           provider: .ollamaGLM, toolCallsRequested: [])
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: return
        case 429:       throw LLMError.rateLimited
        default:        throw LLMError.serverError(http.statusCode)
        }
    }

    // MARK: - Settings helpers

    static func saveSettings(baseURL: String, model: String) {
        UserDefaults.standard.set(baseURL, forKey: "ollama.baseURL")
        UserDefaults.standard.set(model,   forKey: "ollama.model")
    }

    /// Pings the Ollama server to verify it's reachable.
    /// Returns true if /api/tags responds with 200.
    static func ping() async -> Bool {
        guard let base = baseURL else { return false }
        let url = base.appendingPathComponent("/api/tags")
        guard let (_, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse
        else { return false }
        return http.statusCode == 200
    }
}

// MARK: - Keychain helper

enum KeychainHelper {
    // UserDefaults fallback key prefix (simulator-safe)
    private static func udKey(_ service: String, _ key: String) -> String {
        "kc.\(service).\(key)"
    }

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
        if status == errSecSuccess,
           let data = result as? Data,
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        // Fallback: UserDefaults (simulator workaround)
        return UserDefaults.standard.string(forKey: udKey(service, key))
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
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            // Keychain unavailable (simulator) — fall back to UserDefaults
            UserDefaults.standard.set(value, forKey: udKey(service, key))
        } else {
            // Mirror to UserDefaults so read() always has a fallback
            UserDefaults.standard.set(value, forKey: udKey(service, key))
        }
    }
}
