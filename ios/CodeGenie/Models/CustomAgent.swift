import Foundation

/// User-defined agent slot. Joins the swarm after the standard test
/// layer (Architect → Coder ∥ Designer → Integrator → tests → custom).
///
/// `toolAllowlist` is a list of tool names the backend exposes —
/// `read_file`, `grep`, `swiftlint`, etc. An empty list = the agent
/// gets the full registry (matches AgentBlueprint semantics).
struct CustomAgent: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var systemPrompt: String
    var toolAllowlist: [String]
    var enabled: Bool

    init(
        id: UUID = .init(),
        name: String,
        systemPrompt: String,
        toolAllowlist: [String] = [],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.toolAllowlist = toolAllowlist
        self.enabled = enabled
    }

    /// JSON shape the backend's `BuildRequest.custom_agents` expects.
    var wireForm: [String: Any] {
        [
            "name": name,
            "system_prompt": systemPrompt,
            "tool_allowlist": toolAllowlist,
        ]
    }
}

extension CustomAgent {
    /// Curated starter templates. Saves the user from authoring system
    /// prompts cold — they pick a template, tweak the name, save.
    static let templates: [CustomAgent] = [
        .init(
            name: "Accessibility Auditor",
            systemPrompt:
                "You audit the generated SwiftUI views for accessibility regressions. "
                + "Walk every view file. Flag any interactive view without an "
                + "`accessibilityLabel`, any decorative image not marked "
                + "`.accessibilityHidden(true)`, any tap target smaller than 44pt, "
                + "and any text using a hard-coded font size that would defeat "
                + "Dynamic Type. Output JSON findings; severity `error` for any "
                + "missing label on an interactive view.",
            toolAllowlist: ["read_file", "list_dir", "grep", "apple_docs"]
        ),
        .init(
            name: "Privacy Manifest Auditor",
            systemPrompt:
                "You check the project for App Store privacy compliance. Read "
                + "`PrivacyInfo.xcprivacy` and `Info.plist`. Cross-reference any "
                + "API calls (UserDefaults, FileTimestamp, SystemBootTime, etc.) "
                + "the code makes against the declared reasons. Flag missing or "
                + "stale entries. Output JSON findings; severity `critical` for "
                + "any undeclared accessed-API category.",
            toolAllowlist: ["read_file", "list_dir", "grep"]
        ),
        .init(
            name: "Performance Reviewer",
            systemPrompt:
                "You audit the generated SwiftUI views for performance smells. "
                + "Walk every view file. Flag: `ForEach` without an `id:` on a "
                + "non-Identifiable collection, image decoding on the main "
                + "thread, `@StateObject` instances created in `body`, missing "
                + "`LazyVStack` on long lists, and any closure that captures "
                + "`self` strongly inside a long-lived Task. Output JSON findings.",
            toolAllowlist: ["read_file", "list_dir", "grep"]
        ),
    ]
}
