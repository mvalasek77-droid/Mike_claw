import Foundation

// MARK: - Agent Role System
//
// Each role has sharply-defined behavioural constraints and a restricted
// tool pool.  Specialisation prevents role-bleed where an exploration
// agent accidentally overwrites memory, or an execution agent skips
// planning.

enum AgentRole: String, Codable, CaseIterable {
    case explore    // read-only investigation; never writes
    case plan       // synthesises findings into a step list; no side effects
    case execute    // carries out the plan; only role with write access
    case verify     // confirms execute's output; read-only, high scrutiny

    var allowedTier: PermissionTier {
        switch self {
        case .explore:  return .readonly
        case .plan:     return .readonly
        case .execute:  return .privileged
        case .verify:   return .readonly
        }
    }

    var description: String {
        switch self {
        case .explore: return "Read-only investigation of memory and context."
        case .plan:    return "Synthesise findings into an ordered step list."
        case .execute: return "Carry out the plan with write access."
        case .verify:  return "Confirm execution results and flag discrepancies."
        }
    }
}

// MARK: - Typed Event Stream
//
// Every harness operation emits a typed AgentEvent.  These events are the
// single source of truth for logging, debugging, and dual-level verification.
//
// Bug fix #2: `Error` does not conform to `Sendable`, so `AgentEvent` must
// be `@unchecked Sendable` to cross actor boundaries under Swift 6 strict
// concurrency.  We own all construction sites, so this is safe.

enum AgentEvent: @unchecked Sendable {
    case sessionStarted(conversationId: String, role: AgentRole)
    case toolSelected(toolId: String, role: AgentRole)
    case toolValidated(toolId: String, result: HermesToolRegistry.PermissionResult)
    case toolExecuted(toolId: String, success: Bool, durationMs: Int)
    case budgetChecked(remaining: Int, estimatedCost: Int, allowed: Bool)
    case transcriptCompacted(beforeTokens: Int, afterTokens: Int)
    case workflowStepCompleted(stepName: String, index: Int, total: Int)
    case verificationPassed(checkName: String)
    case verificationFailed(checkName: String, reason: String)
    case harnessError(Error)
}

// MARK: - Transcript Message

struct TranscriptMessage: Codable {
    enum Role: String, Codable { case user, assistant, system }
    let role: Role
    let content: String
    let timestamp: Date
    var tokenEstimate: Int    // rough: content.count / 4
    var isPinned: Bool = false  // pinned messages survive compaction

    init(role: Role, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.tokenEstimate = max(1, content.count / 4)
    }
}

// MARK: - HermesAgentHarness

/// Ties all subsystems together.  Entry point for all agentic operations.
/// Use `run(role:task:)` to dispatch a scoped, permission-bounded agent.
actor HermesAgentHarness {
    static let shared = HermesAgentHarness()

    private let memory   = HermesMemory.shared
    private let registry = HermesToolRegistry.shared
    private let session  = HermesSessionState.shared
    private let kairos   = HermesKairos.shared
    private let context  = HermesContextTracker.shared

    private var eventLog: [AgentEvent] = []
    private var transcript: [TranscriptMessage] = []

    // Token ceiling before auto-compaction triggers
    private let compactionThreshold = 6_000

    private init() {}

    // MARK: - Agent dispatch

    /// Run a scoped agent.  Returns a structured result and emits events throughout.
    func run(role: AgentRole, task: String) async throws -> AgentResult {
        let conversationId = await session.conversation.id

        emit(.sessionStarted(conversationId: conversationId, role: role))

        // Pre-turn token budget check
        let budget = await session.tokenBudget
        let allowed = budget.canStartTurn(estimatedCost: 500)
        emit(.budgetChecked(remaining: budget.remaining, estimatedCost: 500, allowed: allowed))
        guard allowed else { throw SessionError.tokenBudgetExhausted(used: budget.used, limit: budget.sessionLimit) }

        // Build context-appropriate tool pool
        let contextTags = Set((await context.currentTopic() ?? "").components(separatedBy: ", "))
        let pool = await registry.assemblePool(for: role, contextTags: contextTags)

        // Record the task in the transcript
        append(message: TranscriptMessage(role: .user, content: task))

        // Auto-compact if approaching threshold
        if transcriptTokenCount() > compactionThreshold {
            await compactTranscript()
        }

        // Build permission context for this agent
        let permCtx = PermissionContext(
            sessionTier: role.allowedTier,
            isInForeground: true,
            tokenBudgetRemaining: budget.remaining,
            kairosActive: false,
            metadata: ["agentRole": role.rawValue]
        )

        // Execute tools in pool order (explore/plan are read-only; execute writes)
        var toolResults: [String: Any] = [:]
        for tool in pool {
            emit(.toolSelected(toolId: tool.id, role: role))

            let validation = await registry.validate(tool: tool.id, context: permCtx)
            emit(.toolValidated(toolId: tool.id, result: validation))
            guard validation.isAllowed else { continue }

            let start = Date()
            let result = await executeTool(tool, context: permCtx)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            emit(.toolExecuted(toolId: tool.id, success: result.success, durationMs: ms))

            if result.success { toolResults[tool.id] = result.value }
        }

        // Build a response via the LLM (Hermes context injected inside HermesLLMClient)
        // .system transcript entries (compaction placeholders) are mapped to .system so
        // ClaudeAPIBridge's guard correctly excludes them from the messages array.
        let llmMessages = transcript.map { msg -> LLMMessage in
            switch msg.role {
            case .user:      return LLMMessage(role: .user,      content: msg.content)
            case .assistant: return LLMMessage(role: .assistant, content: msg.content)
            case .system:    return LLMMessage(role: .system,    content: msg.content)
            }
        }
        // Pass a minimal base prompt — HermesLLMClient.buildSystemPrompt()
        // enriches it with role instructions + full Hermes context automatically.
        let companionName = UserPersona.load().selectedCompanion.name
        let llmRequest = LLMRequest(
            systemPrompt: "You are \(companionName), a deeply personal AI companion. Be helpful, thoughtful, and true to your character.",
            messages: llmMessages,
            tools: pool,
            maxTokens: min(4096, budget.remaining),
            role: role
        )
        let llmResponse = try await HermesLLMClient.shared.complete(request: llmRequest)
        let response = llmResponse.content
        append(message: TranscriptMessage(role: .assistant, content: response))

        // Dual-level verification
        let agentVerification  = verifyAgentOutput(response: response, role: role)
        let harnessVerification = verifyHarness(toolResults: toolResults, role: role)

        for check in agentVerification + harnessVerification {
            emit(check.passed
                 ? .verificationPassed(checkName: check.name)
                 : .verificationFailed(checkName: check.name, reason: check.reason ?? ""))
        }

        // Record token usage (rough estimate)
        let promptEst  = transcriptTokenCount()
        let replyEst   = max(1, response.count / 4)
        try await session.recordTokenUsage(prompt: promptEst, completion: replyEst)

        return AgentResult(
            role: role,
            response: response,
            toolsUsed: Array(toolResults.keys),
            verificationPassed: (agentVerification + harnessVerification).allSatisfy(\.passed),
            events: eventLog
        )
    }

    // MARK: - Tool execution (stub — wire up real tool handlers here)

    private func executeTool(_ tool: ToolDefinition,
                             context: PermissionContext) async -> ToolResult {
        switch tool.id {
        case "hermes.memory.search":
            let recentCtx = await HermesMemoryAgent.shared.run(MemoryAgentMode.recent(count: 5)) ?? "No memory found."
            return ToolResult(success: true, value: recentCtx)
        case "hermes.context.topic":
            let topic = await self.context.currentTopic() ?? "unknown"
            return ToolResult(success: true, value: topic)
        case "hermes.dream.trigger":
            await HermesDreamEngine.shared.runDreamCycle()
            return ToolResult(success: true, value: "dream_complete")
        case "hermes.suggestions.refresh":
            await HermesProactiveEngine.shared.refresh()
            return ToolResult(success: true, value: "suggestions_refreshed")
        case "hermes.session.read":
            let snap = await session.currentSnapshot
            let summary = "Session: \(snap.conversation.id) | msgs: \(snap.conversation.messageCount) | tokens used: \(snap.tokenBudget.used)/\(snap.tokenBudget.sessionLimit)"
            return ToolResult(success: true, value: summary)
        case "hermes.session.write":
            _ = try? await session.saveToDisk()
            return ToolResult(success: true, value: "session_saved")
        default:
            return ToolResult(success: false, value: nil)
        }
    }

    // MARK: - Transcript compaction
    //
    // Keeps pinned messages and the most recent tail intact.
    // Summarises older messages into a single system-role placeholder.
    // This prevents context entropy while staying within token limits.

    private func compactTranscript() async {
        let before = transcriptTokenCount()
        let pinned = transcript.filter(\.isPinned)
        let unpinned = transcript.filter { !$0.isPinned }

        // Keep last 10 unpinned messages; summarise the rest
        let keep = Array(unpinned.suffix(10))
        let summarised = unpinned.dropLast(10)

        if summarised.isEmpty { return }

        let summary = "[Compacted \(summarised.count) earlier messages. " +
                      "Topics covered: \(topicSummary(of: Array(summarised)))]"
        let placeholder = TranscriptMessage(role: .system, content: summary)

        transcript = pinned + [placeholder] + keep
        let after = transcriptTokenCount()
        emit(.transcriptCompacted(beforeTokens: before, afterTokens: after))
    }

    private func topicSummary(of messages: [TranscriptMessage]) -> String {
        let words = messages.map(\.content).joined(separator: " ")
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 4 }
        let freq = Dictionary(words.map { ($0, 1) }, uniquingKeysWith: +)
        return freq.sorted { $0.value > $1.value }.prefix(5).map(\.key).joined(separator: ", ")
    }

    private func transcriptTokenCount() -> Int {
        transcript.reduce(0) { $0 + $1.tokenEstimate }
    }

    private func append(message: TranscriptMessage) {
        transcript.append(message)
    }

    // MARK: - Dual-level verification

    private struct VerificationCheck {
        let name: String
        let passed: Bool
        let reason: String?
    }

    /// Level 1 — verify the agent's own output (content checks).
    private func verifyAgentOutput(response: String, role: AgentRole) -> [VerificationCheck] {
        [
            VerificationCheck(
                name: "response_non_empty",
                passed: !response.isEmpty,
                reason: response.isEmpty ? "Agent produced an empty response." : nil
            ),
            VerificationCheck(
                name: "no_hardcoded_secrets",
                passed: !response.lowercased().contains("api_key") &&
                        !response.lowercased().contains("password"),
                reason: "Response may contain sensitive literals."
            ),
        ]
    }

    /// Level 2 — verify the harness (structural / permission checks).
    private func verifyHarness(toolResults: [String: Any], role: AgentRole) -> [VerificationCheck] {
        let writeToolsUsed = toolResults.keys.filter {
            $0.contains("write") || $0.contains("observe") || $0.contains("dream")
        }
        return [
            VerificationCheck(
                name: "no_writes_in_readonly_role",
                passed: role != .explore || writeToolsUsed.isEmpty,
                reason: writeToolsUsed.isEmpty ? nil
                    : "Explore role invoked write tool(s): \(writeToolsUsed.joined(separator: ", "))"
            ),
        ]
    }

    // MARK: - Event log

    private func emit(_ event: AgentEvent) {
        eventLog.append(event)
        #if DEBUG
        print("[Harness] \(event)")
        #endif
    }

    func recentEvents(limit: Int = 50) -> [AgentEvent] {
        Array(eventLog.suffix(limit))
    }
}

// MARK: - Supporting types

struct ToolResult {
    let success: Bool
    let value: Any?
}

struct AgentResult {
    let role: AgentRole
    let response: String
    let toolsUsed: [String]
    let verificationPassed: Bool
    let events: [AgentEvent]
}
