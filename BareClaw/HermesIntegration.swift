import Foundation

// MARK: - HermesSession

/// Lightweight descriptor of one app session (open → background/close).
struct HermesSession {
    let id: String
    let startedAt: Date
    var messageCount: Int = 0
    var toolCallCount: Int = 0
}

// MARK: - HermesIntegration
//
// High-level API for the rest of BareClaw.
// Fully local — no HTTP, no server, no network permission needed.
//
// Additions over v1:
// - Session lifecycle: logSessionStart / logSessionEnd
// - messageCount / toolCallCount tracked per session
// - Exposes currentSession for context-aware UI

actor HermesIntegration {
    static let shared = HermesIntegration()

    private let memory = HermesMemory.shared
    private let proactive = HermesProactiveEngine.shared
    private let contextTracker = HermesContextTracker.shared

    private(set) var lastError: Error?
    private(set) var currentSession: HermesSession?

    private init() {}

    // MARK: - Session lifecycle

    /// Call when a new conversation starts (app launch, new chat, scene activation).
    func logSessionStart(conversationId: String) async {
        let session = HermesSession(id: conversationId, startedAt: Date())
        currentSession = session
        DiagnosticsLog.info("session", "Session started.", details: ["conversationId": conversationId])
        try? await HermesSessionState.shared.startConversation(id: conversationId)
        await run {
            try await self.memory.observe(
                category: "session_start",
                content: ["conversationId": conversationId],
                metadata: ["importance": 2]
            )
        }
    }

    /// Call when the app backgrounds or a conversation ends.
    func logSessionEnd() async {
        guard let session = currentSession else { return }
        currentSession = nil
        DiagnosticsLog.info(
            "session",
            "Session ended.",
            details: [
                "conversationId": session.id,
                "durationSeconds": "\(Int(Date().timeIntervalSince(session.startedAt)))",
                "messageCount": "\(session.messageCount)",
                "toolCallCount": "\(session.toolCallCount)"
            ]
        )
        await run {
            try await self.memory.observe(
                category: "session_end",
                content: [
                    "conversationId": session.id,
                    "durationSeconds": Int(Date().timeIntervalSince(session.startedAt)),
                    "messageCount": session.messageCount,
                    "toolCallCount": session.toolCallCount
                ],
                metadata: ["importance": 3]
            )
        }
    }

    // MARK: - Logging

    func logUserMessage(_ text: String, in conversationId: String) async {
        currentSession?.messageCount += 1
        DiagnosticsLog.info(
            "chat",
            "User message logged.",
            details: ["conversationId": conversationId, "length": "\(text.count)"]
        )
        await contextTracker.ingest(text: text, role: .user)
        await run {
            try await self.memory.observe(
                category: "user_message",
                content: ["text": text, "conversationId": conversationId],
                metadata: ["importance": 3]
            )
        }
    }

    func logAssistantResponse(_ text: String, toolUses: [String] = []) async {
        DiagnosticsLog.info(
            "chat",
            "Assistant response logged.",
            details: ["length": "\(text.count)", "toolCount": "\(toolUses.count)"]
        )
        await contextTracker.ingest(text: text, role: .assistant)
        await run {
            try await self.memory.observe(
                category: "assistant_response",
                content: ["text": text, "tools": toolUses]
            )
        }
    }

    func logToolExecution(_ toolName: String, success: Bool, duration: TimeInterval) async {
        currentSession?.toolCallCount += 1
        DiagnosticsLog.info(
            "tool",
            "Tool execution logged.",
            details: [
                "tool": toolName,
                "success": "\(success)",
                "durationMs": "\(Int(duration * 1000))"
            ]
        )
        await run {
            try await self.memory.observe(
                category: "tool_exec",
                content: [
                    "tool": toolName,
                    "success": success,
                    "duration_ms": Int(duration * 1000)
                ],
                // Failures matter more: keep them longer, surface in DreamEngine
                metadata: ["importance": success ? 1 : 3]
            )
        }
    }

    func logSystemStatus(_ status: String, details: [String: String] = [:], importance: Int = 3) async {
        var content: [String: Any] = ["status": status]
        if !details.isEmpty {
            content["details"] = details
        }
        DiagnosticsLog.info("system", status, details: details.merging(["importance": "\(importance)"]) { current, _ in current })
        await run {
            try await self.memory.observe(
                category: "system_status",
                content: content,
                metadata: ["importance": importance]
            )
        }
    }

    // MARK: - Queries

    func pollSuggestions() async -> [HermesSuggestion] {
        await proactive.currentSuggestions()
    }

    func currentTopic() async -> String? {
        await contextTracker.currentTopic()
    }

    func searchMemory(query: String, limit: Int = 20) async -> [MemoryEntry] {
        await memory.search(query: query, limit: limit)
    }

    func recentEvents(limit: Int = 50) async -> [MemoryEntry] {
        await memory.recentEntries(limit: limit)
    }

    // MARK: - Private

    @discardableResult
    private func run(_ block: @escaping () async throws -> Void) async -> Bool {
        do {
            try await block()
            return true
        } catch {
            self.lastError = error
            DiagnosticsLog.error("hermes", "Hermes memory/status operation failed.", error: error)
            #if DEBUG
            print("[Hermes] \(error)")
            #endif
            return false
        }
    }
}
