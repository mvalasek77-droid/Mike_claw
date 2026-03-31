import Foundation
import SwiftUI

// MARK: - Chat ViewModel
// Manages a single conversation: sending messages, streaming responses,
// handling tool calls in an agentic loop.

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var conversation: Conversation
    @Published var inputText = ""
    @Published var isThinking = false
    @Published var error: String?

    private var appState: AppState

    init(conversation: Conversation, appState: AppState) {
        self.conversation = conversation
        self.appState = appState
    }

    // MARK: - Send

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }

        inputText = ""
        error = nil

        let userMsg = Message(role: .user, content: text)
        append(userMsg)

        await runAgentLoop()
    }

    // MARK: - Agentic Loop
    // Runs Claude in a loop, executing tool calls until Claude stops with end_turn.

    private func runAgentLoop() async {
        isThinking = true
        defer { isThinking = false }

        var iterations = 0
        let maxIterations = 10  // Safety limit

        while iterations < maxIterations {
            iterations += 1
            do {
                let stopReason = try await streamNextTurn()
                if stopReason != "tool_use" { break }
                // Claude used tools — execute them and loop back
            } catch {
                self.error = error.localizedDescription
                break
            }
        }
    }

    // MARK: - Stream One Turn

    /// Returns the stop_reason ("end_turn", "tool_use", "max_tokens", etc.)
    @discardableResult
    private func streamNextTurn() async throws -> String {
        var assistantMsg = Message(role: .assistant, content: "", isStreaming: true)
        append(assistantMsg)

        var toolUseId = ""
        var toolUseName = ""
        var toolInputBuffer = ""
        var stopReason = "end_turn"

        try await ClaudeService.shared.streamMessage(
            messages: conversation.messages.filter { !$0.isStreaming },
            systemPrompt: conversation.systemPrompt,
            tools: appState.claudeTools,
            apiKey: appState.apiKey
        ) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                switch event {
                case .textDelta(let text):
                    assistantMsg.content += text
                    self.updateLastMessage(assistantMsg)

                case .toolUseStart(let id, let name):
                    toolUseId = id
                    toolUseName = name
                    toolInputBuffer = ""
                    let toolUse = ToolUse(id: UUID(uuidString: id) ?? UUID(), toolName: name, input: [:])
                    assistantMsg.toolUses.append(toolUse)
                    self.updateLastMessage(assistantMsg)

                case .toolInputDelta(let partial):
                    toolInputBuffer += partial

                case .stopReason(let reason):
                    stopReason = reason

                case .done:
                    assistantMsg.isStreaming = false
                    self.updateLastMessage(assistantMsg)
                }
            }
        }

        // If Claude wants to use a tool, execute it
        if stopReason == "tool_use" && !toolUseName.isEmpty {
            let parsedInput = parseJSON(toolInputBuffer)
            await executeToolCall(
                id: toolUseId,
                name: toolUseName,
                input: parsedInput,
                in: &assistantMsg
            )
        }

        appState.updateConversation(conversation)
        return stopReason
    }

    // MARK: - Tool Execution

    private func executeToolCall(
        id: String,
        name: String,
        input: [String: AnyCodable],
        in message: inout Message
    ) async {
        // Update tool use status to running
        if let idx = message.toolUses.firstIndex(where: { $0.id.uuidString == id || $0.toolName == name }) {
            message.toolUses[idx] = ToolUse(
                id: message.toolUses[idx].id,
                toolName: name,
                input: input,
                result: nil,
                status: .running
            )
        }
        updateLastMessage(message)

        var result: String
        var status: ToolUse.Status

        do {
            guard let server = appState.serverForTool(name) else {
                throw ClaudeError.toolExecutionFailed("No MCP server found for tool '\(name)'")
            }
            result = try await MCPService.shared.executeTool(
                named: name,
                arguments: input,
                on: server
            )
            status = .success
        } catch {
            result = "Error: \(error.localizedDescription)"
            status = .failure
        }

        // Update tool use with result
        if let idx = message.toolUses.firstIndex(where: { $0.toolName == name }) {
            message.toolUses[idx].result = result
            message.toolUses[idx].status = status
        }
        updateLastMessage(message)

        // Append tool result message for Claude's context
        let toolResultMsg = Message(
            role: .tool,
            content: result
        )
        append(toolResultMsg)
    }

    // MARK: - Helpers

    private func append(_ message: Message) {
        conversation.messages.append(message)
    }

    private func updateLastMessage(_ message: Message) {
        if let idx = conversation.messages.lastIndex(where: { $0.role == .assistant }) {
            conversation.messages[idx] = message
        }
    }

    private func parseJSON(_ jsonString: String) -> [String: AnyCodable] {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj.mapValues { AnyCodable($0) }
    }

    func clearError() { error = nil }

    func clearConversation() {
        conversation.messages.removeAll()
        appState.updateConversation(conversation)
    }
}
