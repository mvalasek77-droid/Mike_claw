import Foundation

/// Deterministic on-device coach. Question templates are selected by mode and
/// goal keywords; the Skill draft is assembled from the answers. No network,
/// no account — the user's prompts never leave the phone.
enum CoachEngine {

    // MARK: - Goal topics

    enum Topic {
        case writing, code, data, general

        static func detect(in goal: String) -> Topic {
            let lower = goal.lowercased()
            let has: ([String]) -> Bool = { words in words.contains { lower.contains($0) } }
            if has(["debug", "bug", "crash", "error", "code", "compile", "test", "refactor"]) { return .code }
            if has(["email", "write", "draft", "blog", "post", "letter", "summar", "doc"]) { return .writing }
            if has(["api", "data", "database", "file", "deploy", "script", "schema", "migrate"]) { return .data }
            return .general
        }
    }

    // MARK: - Interview questions

    /// 3-5 targeted questions covering goal, audience, acceptance test, and edge cases.
    static func questions(for mode: CoachMode, goal: String) -> [CoachQuestion] {
        let topic = Topic.detect(in: goal)
        var list: [CoachQuestion] = []

        list.append(CoachQuestion(
            prompt: "What does done look like?",
            detail: "The acceptance test: how will you know the output is right?",
            placeholder: "e.g. I could send it without editing"
        ))

        switch topic {
        case .writing:
            list.append(CoachQuestion(
                prompt: "Who is it for, and what tone?",
                detail: "Audience shapes register more than anything else.",
                placeholder: "e.g. my manager — direct but warm"
            ))
        case .code:
            list.append(CoachQuestion(
                prompt: "What's the environment and how do you reproduce it?",
                detail: "Language, framework, and the exact command or steps that show the problem.",
                placeholder: "e.g. Swift 5.10, crashes on launch after tapping Save"
            ))
        case .data, .general:
            list.append(CoachQuestion(
                prompt: "Who consumes the result?",
                detail: "A person, a script, another prompt? It changes the output format.",
                placeholder: "e.g. a teammate reading it on their phone"
            ))
        }

        switch mode {
        case .interview:
            list.append(CoachQuestion(
                prompt: "What should the model ask you before starting?",
                detail: "The one clarifying question you always wish it would ask.",
                placeholder: "e.g. how much context I already have"
            ))
        case .specFirst:
            list.append(CoachQuestion(
                prompt: "What is explicitly out of scope?",
                detail: "Non-goals resolve ambiguity on paper before any work starts.",
                placeholder: "e.g. no redesign, only copy changes"
            ))
        case .subAgents:
            list.append(CoachQuestion(
                prompt: "Which parts are independent of each other?",
                detail: "Independent parts become parallel sub-agent prompts.",
                placeholder: "e.g. research, outline, and examples don't depend on each other"
            ))
        case .verify:
            list.append(CoachQuestion(
                prompt: "What must never happen?",
                detail: "The blast radius: files, APIs, or data the model must not touch blindly.",
                placeholder: "e.g. never write to the production database"
            ))
        }

        list.append(CoachQuestion(
            prompt: "Name one or two edge cases.",
            detail: "The inputs most likely to break a naive attempt.",
            placeholder: "e.g. empty input, or a 10,000-line file"
        ))

        if topic == .data || mode == .verify {
            list.append(CoachQuestion(
                prompt: "What's the riskiest step?",
                detail: "The step you'd double-check if a colleague did this for you.",
                placeholder: "e.g. the schema migration"
            ))
        }

        return Array(list.prefix(5))
    }

    // MARK: - Draft assembly

    static func draft(goal: String, mode: CoachMode, questions: [CoachQuestion], answers: [String]) -> SkillDraft {
        let topic = Topic.detect(in: goal)
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer: (Int) -> String = { index in
            guard index < answers.count else { return "" }
            return answers[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let acceptance = answer(0)
        let audience = answer(1)
        let edgeIndex = min(3, max(0, answers.count - 1))
        let edgeCases = answer(edgeIndex)
        let modeAnswer = answer(2)

        var instructions: [String] = []
        instructions.append("State the goal in one sentence: \(trimmedGoal.isEmpty ? "as described by the user" : trimmedGoal).")
        if !audience.isEmpty {
            instructions.append("Keep the audience in mind: \(audience).")
        }
        instructions.append("Before finishing, check the acceptance test: \(acceptance.isEmpty ? "the user can use the output without editing it" : acceptance).")
        if !edgeCases.isEmpty {
            instructions.append("Handle these edge cases explicitly: \(edgeCases).")
        }

        var specDocument: String? = nil
        var subPrompts: [String] = []
        var synthPrompt: String? = nil
        var checklist: [String] = []

        switch mode {
        case .interview:
            let ask = modeAnswer.isEmpty ? "goal, audience, acceptance test, and edge cases" : modeAnswer
            instructions.insert("Interview first: ask 3-5 short questions (\(ask)) and wait for answers before producing anything.", at: 0)
        case .specFirst:
            specDocument = """
            # Mini spec: \(trimmedGoal)

            Problem — \(trimmedGoal)
            Audience — \(audience.isEmpty ? "unspecified; confirm before drafting" : audience)
            Acceptance — \(acceptance.isEmpty ? "user signs off without edits" : acceptance)
            Out of scope — \(modeAnswer.isEmpty ? "anything not named above" : modeAnswer)
            Edge cases — \(edgeCases.isEmpty ? "none named; probe for them" : edgeCases)
            """
            instructions.insert("Draft the mini spec first and get sign-off before producing the deliverable.", at: 0)
        case .subAgents:
            let split = modeAnswer.isEmpty ? "research, drafting, and critique" : modeAnswer
            subPrompts = [
                "Sub-agent 1 — Research: gather the facts and constraints needed for: \(trimmedGoal). Report findings as bullets, no prose.",
                "Sub-agent 2 — Draft: using the research bullets, produce a first version aimed at \(audience.isEmpty ? "the stated audience" : audience).",
                "Sub-agent 3 — Edge-case hunter: attack the draft with these cases: \(edgeCases.isEmpty ? "empty input, oversized input, and wrong-audience input" : edgeCases).",
                "Sub-agent 4 — Critic: score the draft against the acceptance test: \(acceptance.isEmpty ? "usable without edits" : acceptance)."
            ]
            synthPrompt = "Synth: combine the research, draft, edge-case findings, and critique into one final output. Independent tracks were: \(split). Resolve conflicts in favour of the acceptance test."
            instructions.insert("Run the sub-agent prompts in parallel, then the synth prompt to combine their outputs.", at: 0)
        case .verify:
            checklist = [
                "Restate the goal and confirm it matches: \(trimmedGoal).",
                "List every file, API, or dataset that will be touched — before touching any.",
                "Confirm the never-happen constraint: \(modeAnswer.isEmpty ? "no destructive action without explicit approval" : modeAnswer).",
                "Dry-run the riskiest step and show the expected effect first.",
                "Verify the result against the acceptance test: \(acceptance.isEmpty ? "usable without edits" : acceptance)."
            ]
            instructions.append("Walk the verification checklist before touching real files or APIs.")
        }

        return SkillDraft(
            goal: trimmedGoal,
            mode: mode,
            title: deriveTitle(from: trimmedGoal, topic: topic),
            summary: deriveSummary(goal: trimmedGoal, audience: audience),
            instructions: instructions,
            tools: suggestedTools(for: topic),
            specDocument: specDocument,
            subPrompts: subPrompts,
            synthPrompt: synthPrompt,
            verificationChecklist: checklist,
            learnedRules: edgeCases.isEmpty ? [] : ["Watch for: \(edgeCases)."]
        )
    }

    private static func deriveTitle(from goal: String, topic: Topic) -> String {
        guard !goal.isEmpty else { return "Untitled Skill" }
        var words = goal.split(separator: " ").map(String.init)
        let fillers = ["i", "want", "to", "need", "please", "help", "me", "a", "an", "the", "my"]
        words.removeAll { fillers.contains($0.lowercased()) }
        let core = words.prefix(5).joined(separator: " ")
        let base = core.isEmpty ? goal : core
        return base.prefix(1).uppercased() + base.dropFirst()
    }

    private static func deriveSummary(goal: String, audience: String) -> String {
        let base = goal.isEmpty ? "A reusable Skill from a coach session." : goal
        if audience.isEmpty { return base.prefix(1).uppercased() + base.dropFirst() }
        return "\(base.prefix(1).uppercased() + base.dropFirst()) — for \(audience)."
    }

    private static func suggestedTools(for topic: Topic) -> [String] {
        switch topic {
        case .code: return ["Script: failing test runner", "Reference file: error log"]
        case .writing: return ["Reference file: past examples for tone"]
        case .data: return ["Schema: expected input/output shape"]
        case .general: return []
        }
    }

    // MARK: - Rendering

    /// Renders a saved Skill as a paste-ready prompt.
    static func renderedPrompt(for skill: Skill) -> String {
        var lines: [String] = ["# Skill: \(skill.title)", skill.summary, "", "## Instructions"]
        for (index, step) in skill.instructions.enumerated() {
            lines.append("\(index + 1). \(step)")
        }
        if !skill.tools.isEmpty {
            lines.append("")
            lines.append("## Tools")
            lines.append(contentsOf: skill.tools.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    /// Composes several Skills into one chained prompt — compose, don't clone.
    static func chainPrompt(for skills: [Skill]) -> String {
        var lines: [String] = ["# Chained Skills: \(skills.map(\.title).joined(separator: " → "))", ""]
        for (index, skill) in skills.enumerated() {
            lines.append("## Step \(index + 1): \(skill.title)")
            lines.append(skill.summary)
            for (stepIndex, step) in skill.instructions.enumerated() {
                lines.append("\(stepIndex + 1). \(step)")
            }
            if index < skills.count - 1 {
                lines.append("Pass your output to the next step.")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
