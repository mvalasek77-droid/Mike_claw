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
            #if DEBUG
            print("[Hermes] \(error)")
            #endif
            return false
        }
    }
}
