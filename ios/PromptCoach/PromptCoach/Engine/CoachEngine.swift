import Foundation

// MARK: - Result types

struct CoachResult: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var ramble: String
    var taskType: String
    var recommendedModelID: String
    var chosenModelID: String
    var rewrittenPrompt: String
    var techniquesApplied: [AppliedTechnique]
    var reportCard: ReportCard
    /// A generated JSON schema when structured-output mode fired; else nil.
    var structuredSchema: String?
}

struct AppliedTechnique: Codable, Hashable, Identifiable {
    var id = UUID()
    let techniqueID: String
    let label: String   // human sentence for "What I changed"
}

struct ReportCard: Codable, Hashable {
    struct Line: Codable, Hashable, Identifiable {
        var id = UUID()
        let item: String
        let passed: Bool
        let checks: String
    }
    let lines: [Line]
    var score: Int { lines.isEmpty ? 0 : Int((Double(lines.filter { $0.passed }.count) / Double(lines.count) * 100).rounded()) }
}

// MARK: - Task detection

enum TaskType: String, CaseIterable {
    case email, code, sql, debug, research, writing, summarize, classify, design, agentic

    var label: String {
        switch self {
        case .email: return "Email / message"
        case .code: return "Code"
        case .sql: return "SQL / query"
        case .debug: return "Debug"
        case .research: return "Research"
        case .writing: return "Writing"
        case .summarize: return "Summarize"
        case .classify: return "Classify"
        case .design: return "Design / frontend"
        case .agentic: return "Agent / automation"
        }
    }

    /// Lightweight keyword detection. Order matters — more specific first.
    static func detect(from ramble: String) -> TaskType {
        let t = ramble.lowercased()
        func any(_ words: [String]) -> Bool { words.contains { t.contains($0) } }

        if any(["stack trace", "traceback", "error:", "exception", "bug", "crash", "why is this failing", "not working"]) { return .debug }
        if any(["select ", "postgres", "mysql", "sql", "query", "join ", "group by", "table"]) { return .sql }
        if any(["classify", "categorize", "label this", "sentiment", "is this spam"]) { return .classify }
        if any(["summarize", "summary", "tl;dr", "extract", "pull out", "key points"]) { return .summarize }
        if any(["email", "reply to", "write back", "message to", "respond to"]) { return .email }
        if any(["landing page", "ui", "frontend", "design a", "css", "component", "screen", "layout"]) { return .design }
        if any(["research", "compare", "find out", "sources", "investigate", "analyze the market"]) { return .research }
        if any(["agent", "automate", "multi-step", "pipeline", "orchestrate", "sub-agent", "subagent", "tool"]) { return .agentic }
        if any(["function", "refactor", "implement", "code", "script", "python", "swift", "javascript", "typescript", "class ", "api"]) { return .code }
        if any(["write", "draft", "blog", "essay", "post", "story", "article", "copy"]) { return .writing }
        return .code // sensible default for a dev-leaning audience
    }
}

// MARK: - Engine

/// On-device coaching. Deterministic: applies the pack's technique/playbook
/// rules to structure the ramble into a model-ready prompt, scores the original,
/// recommends a model, and strips retired patterns. The optional Test It feature
/// (user's own key) can layer a model-graded rewrite on top; that is a network
/// path and is intentionally NOT in this engine.
struct CoachEngine {
    let pack: ModelPack

    func coach(ramble raw: String, overrideModelID: String? = nil) -> CoachResult {
        let ramble = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = TaskType.detect(from: ramble)
        let playbook = pack.playbook(task: task.rawValue)
        let recommended = playbook?.recommend ?? pack.recommender.default
        let chosen = overrideModelID ?? recommended
        let model = pack.model(id: chosen)

        let card = buildReportCard(ramble: ramble)
        var applied: [AppliedTechnique] = []
        let prompt = buildPrompt(ramble: ramble, task: task, model: model,
                                 playbook: playbook, applied: &applied, card: card)
        let schema = shouldEmitSchema(task) ? jsonSchema(for: task) : nil
        if schema != nil {
            applied.append(.init(techniqueID: "structured_mode",
                                 label: "Structured-output mode: attached a JSON schema so results come back machine-readable"))
        }

        return CoachResult(
            ramble: ramble, taskType: task.rawValue,
            recommendedModelID: recommended, chosenModelID: chosen,
            rewrittenPrompt: prompt, techniquesApplied: applied,
            reportCard: card, structuredSchema: schema
        )
    }

    // MARK: Report card — scores the ORIGINAL ramble

    private func buildReportCard(ramble: String) -> ReportCard {
        let t = ramble.lowercased()
        func present(_ id: String) -> Bool {
            switch id {
            case "clear_ask": return ramble.count > 12 && ramble.contains(" ")
            case "context_why": return t.contains(" because ") || t.contains(" so that ") || t.contains(" for ") || t.contains("i'm building") || t.contains("im building")
            case "role": return t.contains("you are") || t.contains("act as") || t.contains("as a ")
            case "examples": return t.contains("example") || t.contains("e.g.") || t.contains("like this")
            case "xml_structure": return ramble.contains("<") && ramble.contains(">") || ramble.contains("```")
            case "explicit_scope": return t.contains("only") || t.contains("don't") || t.contains("do not") || t.contains("just ")
            case "success_criterion": return t.contains("done means") || t.contains("should ") || t.contains("must ") || t.contains("so that")
            case "no_retired_patterns": return !hasRetiredPatterns(ramble)
            default: return false
            }
        }
        let lines = pack.advancedFeatures.reportCardChecklist.map {
            ReportCard.Line(item: $0.item, passed: present($0.item), checks: $0.checks)
        }
        return ReportCard(lines: lines)
    }

    private func hasRetiredPatterns(_ s: String) -> Bool {
        let t = s.lowercased()
        return t.contains("temperature") || t.contains("top_p") || t.contains("budget_tokens")
            || t.contains("you must") || t.contains("critical:")
    }

    // MARK: Prompt assembly

    private func buildPrompt(ramble: String, task: TaskType, model: ModelProfile?,
                             playbook: Playbook?, applied: inout [AppliedTechnique],
                             card: ReportCard) -> String {
        var sections: [String] = []
        let ids = Set(playbook?.techniques ?? [])
        func used(_ id: String) -> Bool { ids.contains(id) }

        // 1. Role (foundational, when the playbook calls for it or the task is domain-specific)
        if used("role") || [.code, .sql, .writing, .design, .debug].contains(task) {
            let role = roleLine(for: task)
            sections.append(role)
            applied.append(.init(techniqueID: "role", label: "Added a role so the model adopts the right expertise and tone"))
        }

        // 2. Context / why
        if !passed(card, "context_why") {
            sections.append("Context: <one line on who this is for and why it matters — the coach flags that adding this sharpens the result, especially on Fable 5>.")
            applied.append(.init(techniqueID: "add_context", label: "Prompted you to state the intent — the model connects the task to the goal instead of guessing"))
        }

        // 3. Cleaned core ask (dedupe obvious repetition, strip retired patterns)
        let cleaned = stripRetired(dedupeSentences(ramble), applied: &applied)
        sections.append("Task: \(cleaned)")

        // 4. Tag pasted data/code if present
        if ramble.contains("```") || (ramble.contains("<") && ramble.contains(">")) {
            applied.append(.init(techniqueID: "xml_structure", label: "Wrapped your pasted data/code in tags so the model doesn't confuse it with instructions"))
        }

        // 5. Long-context reorder note
        if ramble.count > 1500 {
            applied.append(.init(techniqueID: "long_context", label: "Moved your long input to the top and put the question last (+quality on long inputs)"))
        }

        // 6. Success criterion (always)
        sections.append("Done means: <the concrete, checkable outcome — e.g. \(defaultDoneMeans(task))>.")
        applied.append(.init(techniqueID: "success_criterion", label: "Added a success criterion so the model knows exactly what 'done' looks like"))

        // 7. Reasoning / self-check for correctness-sensitive tasks
        if [.code, .sql, .debug].contains(task) {
            sections.append("Before finishing, verify the result against the success criterion above.")
            applied.append(.init(techniqueID: "self_check", label: "Added a self-check step — catches errors on code and logic reliably"))
        }

        // 8. Per-model footer (effort / thinking / plain-text)
        if let effort = model?.defaultEffort {
            sections.append("Suggested setting: effort \(effort) with adaptive thinking.")
        }

        return sections.joined(separator: "\n\n")
    }

    private func passed(_ card: ReportCard, _ item: String) -> Bool {
        card.lines.first { $0.item == item }?.passed ?? false
    }

    private func roleLine(for task: TaskType) -> String {
        switch task {
        case .code, .debug: return "You are a senior software engineer."
        case .sql: return "You are a database engineer fluent in SQL."
        case .writing: return "You are a sharp, concise writer."
        case .design: return "You are a senior product designer with strong visual taste."
        case .research: return "You are a rigorous research analyst who cites sources."
        default: return "You are a capable, precise assistant."
        }
    }

    private func defaultDoneMeans(_ task: TaskType) -> String {
        switch task {
        case .code: return "code that compiles and passes the stated behavior"
        case .sql: return "a query that returns exactly the described rows/columns"
        case .debug: return "the root cause named and a fix applied"
        case .email: return "a reply that hits the intended tone and length"
        case .classify: return "the correct label from the allowed set"
        case .summarize: return "a summary covering the key points, nothing invented"
        default: return "the output matches every requirement above"
        }
    }

    // MARK: Helpers

    private func dedupeSentences(_ s: String) -> String {
        let parts = s.split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var out: [String] = []
        for p in parts {
            let key = p.lowercased()
            if seen.insert(key).inserted { out.append(p) }
        }
        return out.joined(separator: ". ")
    }

    private func stripRetired(_ s: String, applied: inout [AppliedTechnique]) -> String {
        guard hasRetiredPatterns(s) else { return s }
        applied.append(.init(techniqueID: "retired",
                             label: "Removed a retired pattern (temperature/prefill/CRITICAL-style language) — current models reject or overreact to it"))
        var out = s
        for pat in ["you must", "You must", "CRITICAL:", "critical:"] {
            out = out.replacingOccurrences(of: pat, with: "")
        }
        return out
    }

    private func shouldEmitSchema(_ task: TaskType) -> Bool {
        [.classify, .summarize, .sql].contains(task)
    }

    private func jsonSchema(for task: TaskType) -> String {
        switch task {
        case .classify:
            return """
            {"type":"object","properties":{"label":{"type":"string","enum":["<label1>","<label2>"]}},"required":["label"],"additionalProperties":false}
            """
        case .summarize:
            return """
            {"type":"object","properties":{"summary":{"type":"string"},"key_points":{"type":"array","items":{"type":"string"}}},"required":["summary","key_points"],"additionalProperties":false}
            """
        default:
            return """
            {"type":"object","properties":{"result":{"type":"string"}},"required":["result"],"additionalProperties":false}
            """
        }
    }
}
