import Foundation
import SwiftUI

// MARK: - Global App State

@MainActor
final class AppState: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var activeConversationId: UUID?
    @Published var mcpServers: [MCPServerConfig] = []
    @Published var availableTools: [MCPTool] = []
    @Published var isToolsLoading = false

    // Settings
    @Published var apiKey: String {
        didSet { KeychainHelper.save(apiKey, key: "anthropic_api_key") }
    }
    @Published var defaultSystemPrompt: String {
        didSet { UserDefaults.standard.set(defaultSystemPrompt, forKey: "default_system_prompt") }
    }
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selected_model") }
    }

    var activeConversation: Conversation? {
        get { conversations.first { $0.id == activeConversationId } }
    }

    init() {
        self.apiKey = KeychainHelper.load(key: "anthropic_api_key") ?? ""
        self.defaultSystemPrompt = UserDefaults.standard.string(forKey: "default_system_prompt") ?? Self.openClawSystemPrompt
        self.selectedModel = UserDefaults.standard.string(forKey: "selected_model") ?? "claude-sonnet-4-6"
        self.mcpServers = Self.loadMCPServers()
        self.conversations = Self.loadConversations()
    }

    // MARK: - Conversation Management

    func newConversation(title: String = "New Chat") -> Conversation {
        let convo = Conversation(title: title, systemPrompt: defaultSystemPrompt)
        conversations.insert(convo, at: 0)
        activeConversationId = convo.id
        save()
        return convo
    }

    func updateConversation(_ conversation: Conversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
            conversations[idx].updatedAt = Date()
        }
        save()
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if activeConversationId == id {
            activeConversationId = conversations.first?.id
        }
        save()
    }

    // MARK: - MCP Tool Discovery

    func refreshTools() async {
        isToolsLoading = true
        var tools: [MCPTool] = []
        for server in mcpServers where server.isEnabled {
            if let discovered = try? await MCPService.shared.discoverTools(from: server) {
                tools.append(contentsOf: discovered)
            }
        }
        availableTools = tools
        isToolsLoading = false
    }

    func addMCPServer(_ server: MCPServerConfig) {
        mcpServers.append(server)
        saveMCPServers()
        Task { await refreshTools() }
    }

    func removeMCPServer(_ id: UUID) {
        mcpServers.removeAll { $0.id == id }
        availableTools.removeAll { $0.serverId == id }
        saveMCPServers()
    }

    func toggleMCPServer(_ id: UUID) {
        if let idx = mcpServers.firstIndex(where: { $0.id == id }) {
            mcpServers[idx].isEnabled.toggle()
            saveMCPServers()
            Task { await refreshTools() }
        }
    }

    // MARK: - Claude Tools (from MCP)

    var claudeTools: [ClaudeTool] {
        availableTools.map { tool in
            ClaudeTool(
                name: tool.name,
                description: tool.description,
                input_schema: ClaudeToolSchema(
                    type: tool.inputSchema.type,
                    properties: tool.inputSchema.properties,
                    required: tool.inputSchema.required
                )
            )
        }
    }

    func serverForTool(_ toolName: String) -> MCPServerConfig? {
        guard let tool = availableTools.first(where: { $0.name == toolName }) else { return nil }
        return mcpServers.first { $0.id == tool.serverId }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(data, forKey: "conversations")
        }
    }

    private func saveMCPServers() {
        if let data = try? JSONEncoder().encode(mcpServers) {
            UserDefaults.standard.set(data, forKey: "mcp_servers")
        }
    }

    private static func loadConversations() -> [Conversation] {
        guard let data = UserDefaults.standard.data(forKey: "conversations"),
              let conversations = try? JSONDecoder().decode([Conversation].self, from: data)
        else { return [] }
        return conversations
    }

    private static func loadMCPServers() -> [MCPServerConfig] {
        guard let data = UserDefaults.standard.data(forKey: "mcp_servers"),
              let servers = try? JSONDecoder().decode([MCPServerConfig].self, from: data)
        else { return [] }
        return servers
    }

    // MARK: - Default System Prompt (Openclaw style)

    static let openClawSystemPrompt = """
    You are an intelligent agentic assistant running on iPhone. You have access to tools provided \
    by MCP servers, and you can take actions on the user's behalf.

    You are direct, efficient, and proactive. You use available tools when they help accomplish \
    the user's goal. You explain what you're doing and why.

    When given a task:
    1. Analyze what's needed
    2. Use tools strategically — don't call tools unnecessarily
    3. Synthesize results into a clear, useful response
    4. Suggest follow-up actions when relevant

    You run natively on iPhone and respect user privacy. All API calls go directly from this \
    device to the service — no intermediary servers.
    """
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(_ value: String, key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
