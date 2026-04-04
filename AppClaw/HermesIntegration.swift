import Foundation

// MARK: - HermesIntegration
//
// High-level API used by the rest of AppClaw.
// Fully local — no HTTP, no server, no network permission needed.
// All data lives in the app's sandboxed Documents/hermes/ directory.

actor HermesIntegration {
    static let shared = HermesIntegration()

    private let memory = HermesMemory.shared
    private let proactive = HermesProactiveEngine.shared

    private(set) var lastError: Error?

    private init() {}

    // MARK: - Logging (fire-and-forget)

    /// Call when the user sends a message.
    func logUserMessage(_ text: String, in conversationId: String) async {
        await run {
            try await self.memory.observe(
                category: "user_message",
                content: ["text": text, "conversationId": conversationId],
                metadata: ["importance": 3]
            )
        }
    }

    /// Call when the assistant responds.
    func logAssistantResponse(_ text: String, toolUses: [String] = []) async {
        await run {
            try await self.memory.observe(
                category: "assistant_response",
                content: ["text": text, "tools": toolUses]
            )
        }
    }

    /// Call after any tool execution.
    func logToolExecution(_ toolName: String, success: Bool, duration: TimeInterval) async {
        await run {
            try await self.memory.observe(
                category: "tool_exec",
                content: [
                    "tool": toolName,
                    "success": success,
                    "duration_ms": Int(duration * 1000)
                ],
                metadata: ["importance": success ? 1 : 3]  // failures are more important to remember
            )
        }
    }

    // MARK: - Suggestions

    /// Returns proactive suggestions based on patterns in local memory.
    func pollSuggestions() async -> [HermesSuggestion] {
        await proactive.currentSuggestions()
    }

    // MARK: - Queries

    /// Keyword search across local memory.
    func searchMemory(query: String, limit: Int = 20) async -> [MemoryEntry] {
        await memory.search(query: query, limit: limit)
    }

    /// Most recent N events.
    func recentEvents(limit: Int = 50) async -> [MemoryEntry] {
        await memory.recentEntries(limit: limit)
    }

    // MARK: - Private

    private func run(_ block: @escaping () async throws -> Void) async {
        do {
            try await block()
        } catch {
            self.lastError = error
            #if DEBUG
            print("[Hermes] \(error)")
            #endif
        }
    }
}
