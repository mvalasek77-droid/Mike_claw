import SwiftUI

/// Settings sub-screen for user-defined agent slots. Each custom
/// agent joins the swarm after the standard test layer with its own
/// system prompt + tool allowlist.
///
/// The form is intentionally minimal — pick a template, tweak the
/// name, save. Power users can drop into the system-prompt textarea
/// and write from scratch.
struct CustomAgentsView: View {
    @StateObject private var creds = Credentials.shared
    @State private var editing: CustomAgent?
    @State private var deletePending: CustomAgent?
    @State private var viewingRun: CustomAgent?

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if creds.customAgents.isEmpty {
                        emptyState
                    } else {
                        agentList
                    }
                    templatesBlock
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $editing) { agent in
            CustomAgentEditor(initial: agent) { updated in
                if let updated { creds.upsertCustomAgent(updated) }
                editing = nil
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $viewingRun) { agent in
            CustomAgentLastRunView(agent: agent)
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .alert("Delete custom agent?", isPresented: Binding(
            get: { deletePending != nil },
            set: { if !$0 { deletePending = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let a = deletePending { creds.removeCustomAgent(id: a.id) }
                deletePending = nil
            }
            Button("Cancel", role: .cancel) { deletePending = nil }
        } message: {
            Text(deletePending?.name ?? "")
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom agents")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Add your own swarm member. Runs after the standard test layer with the tools you allowlist.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        GlassCard(title: "No custom agents yet", icon: "person.crop.circle.badge.plus", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add one to extend what CodeGenie checks at the end of every build.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                PrimaryButton(title: "New agent", systemImage: "plus", style: .filled) {
                    editing = CustomAgent(name: "", systemPrompt: "")
                }
            }
        }
    }

    private var agentList: some View {
        VStack(spacing: 10) {
            ForEach(creds.customAgents) { agent in
                AgentCard(
                    agent: agent,
                    onEdit: { editing = agent },
                    onShowLastRun: { viewingRun = agent },
                    onToggle: { on in
                        var copy = agent; copy.enabled = on
                        creds.upsertCustomAgent(copy)
                    },
                    onDelete: { deletePending = agent }
                )
            }
            Button {
                editing = CustomAgent(name: "", systemPrompt: "")
                Haptics.selection()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New agent")
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(LiquidGlass.primaryText)
                .background(LiquidGlass.auroraGradient.opacity(0.85), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var templatesBlock: some View {
        GlassCard(title: "Templates", icon: "square.stack.fill", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tap to add a polished starting point. You can tweak the name + prompt before saving.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                ForEach(CustomAgent.templates) { template in
                    Button {
                        editing = CustomAgent(
                            name: template.name,
                            systemPrompt: template.systemPrompt,
                            toolAllowlist: template.toolAllowlist
                        )
                        Haptics.selection()
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText)
                                Text(template.systemPrompt.prefix(80) + "…")
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(LiquidGlass.accent)
                        }
                        .padding(10)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Add template \(template.name)")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct AgentCard: View {
    let agent: CustomAgent
    let onEdit: () -> Void
    let onShowLastRun: () -> Void
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        GlassSurface(tier: .raised, corner: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "🧩".isEmpty ? "person.crop.circle" : "person.crop.circle")
                        .foregroundStyle(LiquidGlass.accent)
                    Text(agent.name.isEmpty ? "Untitled" : agent.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Spacer()
                    Toggle("", isOn: Binding(get: { agent.enabled }, set: { onToggle($0) }))
                        .labelsHidden()
                        .tint(LiquidGlass.success)
                }
                Text(agent.systemPrompt)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .lineLimit(3)
                if !agent.toolAllowlist.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(agent.toolAllowlist, id: \.self) { tool in
                                Text(tool)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.white.opacity(0.08), in: Capsule())
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                            }
                        }
                    }
                }
                HStack(spacing: 14) {
                    Button("Edit", action: onEdit)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                    Button("Last run", action: onShowLastRun)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accentSecondary)
                    Spacer()
                    Button("Delete", role: .destructive, action: onDelete)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red.opacity(0.85))
                }
            }
            .padding(14)
        }
    }
}

/// Inline editor sheet for a single agent slot.
private struct CustomAgentEditor: View {
    let initial: CustomAgent
    let onSave: (CustomAgent?) -> Void

    @State private var name: String
    @State private var prompt: String
    @State private var allowlistText: String
    @Environment(\.dismiss) private var dismiss

    init(initial: CustomAgent, onSave: @escaping (CustomAgent?) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _name = State(initialValue: initial.name)
        _prompt = State(initialValue: initial.systemPrompt)
        _allowlistText = State(initialValue: initial.toolAllowlist.joined(separator: ", "))
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text(initial.name.isEmpty ? "New agent" : "Edit agent")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Spacer()
                    }

                    GlassCard(title: "Name", icon: "person.crop.circle", tint: LiquidGlass.accent) {
                        TextField("Accessibility Auditor", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .padding(10)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
                    }

                    GlassCard(title: "System prompt", icon: "text.alignleft", tint: LiquidGlass.accentSecondary) {
                        TextEditor(text: $prompt)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 160)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .padding(8)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }

                    GlassCard(title: "Tool allowlist", icon: "wrench.and.screwdriver.fill", tint: LiquidGlass.warning) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Comma-separated. Leave empty for full access. Available: read_file, list_dir, grep, swiftlint, shell, apple_docs, recall_memory.")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                            TextField("read_file, grep, swiftlint", text: $allowlistText)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(LiquidGlass.primaryText)
                                .padding(10)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
                        }
                    }

                    HStack(spacing: 10) {
                        PrimaryButton(title: "Cancel", systemImage: "xmark", style: .ghost) {
                            onSave(nil); dismiss()
                        }
                        PrimaryButton(title: "Save", systemImage: "checkmark", style: .filled) {
                            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                            let tools = allowlistText
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else {
                                Haptics.error(); return
                            }
                            var copy = initial
                            copy.name = trimmedName
                            copy.systemPrompt = trimmedPrompt
                            copy.toolAllowlist = tools
                            onSave(copy)
                            dismiss()
                        }
                    }
                    .padding(.top, 4)
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
