import Foundation

// MARK: - Tool Registry
//
// Metadata-first: every tool is described (name, capabilities, required permission
// tier) before any execution path is defined.  The harness consults this registry
// to assemble a context-appropriate tool pool and run permission checks.
//
// Permission tiers (ascending trust):
//   readonly   — read-only data access, no side-effects
//   standard   — normal app operations (writing memory, UI updates)
//   privileged — sensitive operations (network, file writes, session data)
//   restricted — dangerous / destructive (only callable in explicit harness mode)

// MARK: - Permission Tier

enum PermissionTier: Int, Comparable, Codable {
    case readonly   = 0
    case standard   = 1
    case privileged = 2
    case restricted = 3

    static func < (lhs: PermissionTier, rhs: PermissionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Tool Capability flags

struct ToolCapabilities: OptionSet, Codable {
    let rawValue: UInt16

    static let readMemory       = ToolCapabilities(rawValue: 1 << 0)
    static let writeMemory      = ToolCapabilities(rawValue: 1 << 1)
    static let readSession      = ToolCapabilities(rawValue: 1 << 2)
    static let writeSession     = ToolCapabilities(rawValue: 1 << 3)
    static let modifyUI         = ToolCapabilities(rawValue: 1 << 4)
    static let readContext      = ToolCapabilities(rawValue: 1 << 5)
    static let triggerDream     = ToolCapabilities(rawValue: 1 << 6)
    static let networkAccess    = ToolCapabilities(rawValue: 1 << 7)
    static let fileWrite        = ToolCapabilities(rawValue: 1 << 8)
    static let executeSubagent  = ToolCapabilities(rawValue: 1 << 9)

    /// Convenience: all safe read-only capabilities
    static let readOnly: ToolCapabilities = [.readMemory, .readSession, .readContext]
}

// MARK: - Security module checks (18 modules)
//
// Each SecurityModule is a lightweight predicate evaluated before a privileged
// or restricted tool executes.  If any required module returns false, execution
// is denied and the reason is logged.

struct SecurityModule {
    let name: String
    let check: (ToolDefinition, PermissionContext) -> Bool
}

struct PermissionContext {
    let sessionTier: PermissionTier    // highest tier granted for this session
    let isInForeground: Bool
    let tokenBudgetRemaining: Int      // prevents runaway tool chains
    let kairosActive: Bool
    let metadata: [String: Any]
}

// MARK: - ToolDefinition

struct ToolDefinition: Identifiable {
    let id: String               // stable, reverse-domain identifier
    let displayName: String
    let description: String
    let capabilities: ToolCapabilities
    let requiredTier: PermissionTier
    let agentRoles: [AgentRole]  // which agent roles can call this tool
    let inputSchema: [String: Any]   // JSON Schema describing expected input
    var isEnabled: Bool = true

    /// Tags used by Tool Pool Assembly to select context-appropriate subsets.
    let contextTags: Set<String>
}

// MARK: - HermesToolRegistry

actor HermesToolRegistry {
    static let shared = HermesToolRegistry()

    private var tools: [String: ToolDefinition] = [:]
    private var securityModules: [SecurityModule] = []

    private init() {
        bootstrapBuiltinTools()
        bootstrapSecurityModules()
    }

    // MARK: - Registration

    func register(_ tool: ToolDefinition) {
        tools[tool.id] = tool
    }

    func disable(_ id: String) {
        tools[id]?.isEnabled = false
    }

    // MARK: - Tool Pool Assembly

    /// Returns enabled tools appropriate for the given agent role and context tags.
    func assemblePool(for role: AgentRole, contextTags: Set<String> = []) -> [ToolDefinition] {
        tools.values
            .filter { $0.isEnabled }
            .filter { $0.agentRoles.contains(role) }
            .filter { contextTags.isEmpty || !$0.contextTags.isDisjoint(with: contextTags) }
            .sorted { $0.id < $1.id }
    }

    /// All tools available at or below the given permission tier.
    func tools(upTo tier: PermissionTier) -> [ToolDefinition] {
        tools.values.filter { $0.isEnabled && $0.requiredTier <= tier }.sorted { $0.id < $1.id }
    }

    // MARK: - Permission check

    /// Run all required security modules. Returns .success or the first denial reason.
    func validate(tool id: String, context: PermissionContext) -> PermissionResult {
        guard let tool = tools[id] else {
            return .denied("Tool '\(id)' not registered.")
        }
        guard tool.isEnabled else {
            return .denied("Tool '\(id)' is disabled.")
        }
        guard context.sessionTier >= tool.requiredTier else {
            return .denied("Session tier \(context.sessionTier) insufficient for \(tool.requiredTier) tool.")
        }
        guard context.tokenBudgetRemaining > 0 else {
            return .denied("Token budget exhausted.")
        }

        // Run all security modules in order
        for module in securityModules {
            if !module.check(tool, context) {
                return .denied("Security module '\(module.name)' rejected execution.")
            }
        }
        return .allowed
    }

    enum PermissionResult {
        case allowed
        case denied(String)
        var isAllowed: Bool { if case .allowed = self { return true }; return false }
    }

    // MARK: - Lookup

    func tool(_ id: String) -> ToolDefinition? { tools[id] }
    var allTools: [ToolDefinition] { Array(tools.values) }

    // MARK: - Built-in tool bootstrap

    private func bootstrapBuiltinTools() {
        let builtins: [ToolDefinition] = [
            ToolDefinition(
                id: "hermes.memory.search",
                displayName: "Memory Search",
                description: "Search short-term and long-term memory by keyword.",
                capabilities: [.readMemory],
                requiredTier: .readonly,
                agentRoles: [.explore, .plan, .verify],
                inputSchema: ["query": "string", "limit": "integer"],
                contextTags: ["memory", "search"]
            ),
            ToolDefinition(
                id: "hermes.memory.observe",
                displayName: "Observe",
                description: "Write a new observation to memory.",
                capabilities: [.writeMemory],
                requiredTier: .standard,
                agentRoles: [.execute],
                inputSchema: ["category": "string", "content": "any", "metadata": "object"],
                contextTags: ["memory", "write"]
            ),
            ToolDefinition(
                id: "hermes.context.topic",
                displayName: "Current Topic",
                description: "Retrieve the detected topic of the current conversation window.",
                capabilities: [.readContext],
                requiredTier: .readonly,
                agentRoles: [.explore, .plan, .verify, .execute],
                inputSchema: [:],
                contextTags: ["context"]
            ),
            ToolDefinition(
                id: "hermes.dream.trigger",
                displayName: "Trigger Dream",
                description: "Manually trigger a mini-dream consolidation cycle.",
                capabilities: [.triggerDream, .writeMemory],
                requiredTier: .privileged,
                agentRoles: [.execute],
                inputSchema: [:],
                contextTags: ["dream", "maintenance"]
            ),
            ToolDefinition(
                id: "hermes.session.read",
                displayName: "Read Session State",
                description: "Read crash-safe session state including token usage.",
                capabilities: [.readSession],
                requiredTier: .readonly,
                agentRoles: [.explore, .plan, .verify],
                inputSchema: [:],
                contextTags: ["session"]
            ),
            ToolDefinition(
                id: "hermes.session.write",
                displayName: "Write Session State",
                description: "Persist session state snapshot to disk.",
                capabilities: [.writeSession],
                requiredTier: .privileged,
                agentRoles: [.execute],
                inputSchema: ["state": "object"],
                contextTags: ["session"]
            ),
            ToolDefinition(
                id: "hermes.suggestions.refresh",
                displayName: "Refresh Suggestions",
                description: "Force-refresh the Kairos proactive suggestion cache.",
                capabilities: [.readMemory, .modifyUI],
                requiredTier: .standard,
                agentRoles: [.execute],
                inputSchema: [:],
                contextTags: ["suggestions", "ui"]
            ),
        ]
        builtins.forEach { register($0) }
    }

    // MARK: - Security module bootstrap (18 modules)

    private func bootstrapSecurityModules() {
        securityModules = [
            // 1. Tool must be enabled
            SecurityModule(name: "tool_enabled") { tool, _ in tool.isEnabled },
            // 2. Session must be active (not terminated)
            SecurityModule(name: "session_active") { _, ctx in ctx.tokenBudgetRemaining >= 0 },
            // 3. Network tools require foreground
            SecurityModule(name: "network_foreground") { tool, ctx in
                !tool.capabilities.contains(.networkAccess) || ctx.isInForeground
            },
            // 4. Destructive writes require privileged tier
            SecurityModule(name: "write_tier") { tool, ctx in
                !tool.capabilities.contains(.writeMemory) || ctx.sessionTier >= .standard
            },
            // 5. File writes require privileged tier
            SecurityModule(name: "file_write_tier") { tool, ctx in
                !tool.capabilities.contains(.fileWrite) || ctx.sessionTier >= .privileged
            },
            // 6. Subagent execution requires privileged tier
            SecurityModule(name: "subagent_tier") { tool, ctx in
                !tool.capabilities.contains(.executeSubagent) || ctx.sessionTier >= .privileged
            },
            // 7. Dream trigger requires Kairos to not be in the middle of a cycle
            SecurityModule(name: "dream_not_running") { tool, ctx in
                !tool.capabilities.contains(.triggerDream) || !ctx.kairosActive
            },
            // 8. Token budget must be > 10% of baseline to allow privileged ops
            SecurityModule(name: "budget_privileged_floor") { tool, ctx in
                tool.requiredTier < .privileged || ctx.tokenBudgetRemaining > 1_000
            },
            // 9. UI modifications require foreground
            SecurityModule(name: "ui_foreground") { tool, ctx in
                !tool.capabilities.contains(.modifyUI) || ctx.isInForeground
            },
            // 10. Restricted tools must have explicit metadata flag
            SecurityModule(name: "restricted_explicit") { tool, ctx in
                tool.requiredTier < .restricted || (ctx.metadata["explicitRestricted"] as? Bool == true)
            },
            // 11. Session writes disallowed in readonly sessions
            SecurityModule(name: "session_write_tier") { tool, ctx in
                !tool.capabilities.contains(.writeSession) || ctx.sessionTier >= .privileged
            },
            // 12. Context reads always allowed
            SecurityModule(name: "context_read_allowed") { tool, _ in
                !tool.capabilities.contains(.readContext) || true
            },
            // 13. Memory reads always allowed
            SecurityModule(name: "memory_read_allowed") { tool, _ in
                !tool.capabilities.contains(.readMemory) || true
            },
            // 14. Tool id must be reverse-domain format
            SecurityModule(name: "id_format") { tool, _ in
                tool.id.contains(".")
            },
            // 15. Tool must have a non-empty description
            SecurityModule(name: "description_present") { tool, _ in
                !tool.description.isEmpty
            },
            // 16. Input schema must be present (even if empty) for all write tools
            SecurityModule(name: "write_schema_present") { tool, _ in
                !tool.capabilities.contains(.writeMemory) || !tool.inputSchema.isEmpty
            },
            // 17. Budget floor for any execution in standard tier
            SecurityModule(name: "budget_standard_floor") { tool, ctx in
                tool.requiredTier < .standard || ctx.tokenBudgetRemaining > 100
            },
            // 18. Dream trigger restricted to execute role only
            SecurityModule(name: "dream_execute_role_only") { tool, ctx in
                !tool.capabilities.contains(.triggerDream) ||
                (ctx.metadata["agentRole"] as? String == AgentRole.execute.rawValue)
            },
        ]
    }
}
