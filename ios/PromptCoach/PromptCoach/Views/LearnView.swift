import SwiftUI

/// Short explainer for a prompt-engineering technique — the "teaching" surface.
/// Every coached prompt links here so users learn the method, not just the result.
struct LearnView: View {
    let technique: Technique
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(technique.name)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Glass.primaryText)
                        badge(technique.category)
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("When to use it")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Glass.primaryText.opacity(0.55)).textCase(.uppercase)
                                Text(technique.when)
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundStyle(Glass.primaryText.opacity(0.9))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                        }
                        if let detail = Self.details[technique.id] {
                            GlassCard {
                                Text(detail)
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundStyle(Glass.primaryText.opacity(0.9))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func badge(_ category: String) -> some View {
        Text(category.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(Glass.accent)
            .background(Glass.accent.opacity(0.15), in: Capsule())
    }

    /// Longer explainers keyed by technique id. Sourced from Anthropic's
    /// official prompt-engineering guidance.
    static let details: [String: String] = [
        "role": "Setting a role in the system prompt — even one sentence — focuses Claude's tone and expertise for your use case. 'You are a senior Python reviewer' measurably changes the output.",
        "add_context": "Explaining WHY behind an instruction lets Claude generalize correctly. 'Never use ellipses' is weak; 'this is read aloud by text-to-speech, which can't pronounce ellipses' is strong.",
        "examples": "A few well-chosen examples (3–5) are the most reliable way to lock output format and tone. Make them relevant, diverse, and wrapped in <example> tags.",
        "xml_structure": "XML tags let Claude tell instructions from context from data. Wrap each kind of content in its own tag so nothing gets confused.",
        "success_criterion": "State how the result will be judged — 'done means…'. The single highest-leverage addition to almost any prompt.",
        "self_check": "Append 'before you finish, verify your answer against [criteria]'. Catches errors reliably, especially for code and math.",
        "adaptive_thinking": "On current models, reasoning depth is set by the effort level and query complexity — not a token budget. Ask it to 'think it through' rather than prescribing steps.",
        "long_context": "Put long documents at the top and the question at the end — up to +30% quality on multi-document tasks. Wrap each doc in tags.",
        "structured_mode": "For machine-readable results, use structured outputs with a JSON schema instead of an old-style prefill (which current models reject).",
        "tool_triggers": "Tell the model WHEN to use a tool ('call this when the answer depends on current prices'), in the tool's own description. Biggest lever for Opus 4.8's conservative triggering.",
        "anti_slop_frontend": "For UI work, demand distinctive typography, a committed color theme, and purposeful motion; explicitly ban generic fonts and clichéd purple-on-white gradients."
    ]
}
