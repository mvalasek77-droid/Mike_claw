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

    /// True once the Sharpen (meta-prompting) pass has restructured it.
    ///
    /// Stored as `Bool?` on purpose: Swift's synthesized decoder only falls
    /// back for Optionals, so a non-optional `Bool` here — even with a default
    /// — would throw on history JSON written before this field existed and
    /// silently wipe the user's saved sessions. Use `isSharpened`.
    var sharpened: Bool?
    var isSharpened: Bool {
        get { sharpened ?? false }
        set { sharpened = newValue }
    }

    /// Approximate token counts and input cost for this prompt on the chosen
    /// model. Optional for the same history-compatibility reason as
    /// `sharpened`, and nil when the pack ships no `token_estimation` block.
    var tokenReport: TokenReport?
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

    /// Defaults learned from this user's own sessions. `.none` is a fresh
    /// install, so the engine's output is identical for a first-run user and
    /// for a test that doesn't opt in.
    var learning: LearningSnapshot = .none

    var estimator: TokenEstimator { TokenEstimator(config: pack.tokenEstimation) }

    /// A technique the user has muted. Muting only ever *subtracts* — which
    /// is what makes the "never learn away a hard API fact" guardrail hold by
    /// construction: nothing learned can add a parameter a model rejects.
    private func muted(_ id: String) -> Bool { learning.mutedTechniques.contains(id) }

    func coach(ramble raw: String, overrideModelID: String? = nil) -> CoachResult {
        let ramble = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = TaskType.detect(from: ramble)
        let playbook = pack.playbook(task: task.rawValue)
        let packRecommended = playbook?.recommend ?? pack.recommender.default

        // Learning shifts the *default* only. An explicit override always
        // wins, and the chip still says which model this user prefers rather
        // than silently pretending the pack recommended it.
        var recommended = packRecommended
        var learnedShift = false
        if let preferred = learning.preferredModelByTask[task.rawValue],
           preferred != packRecommended, pack.model(id: preferred) != nil {
            recommended = preferred
            learnedShift = true
        }

        let chosen = overrideModelID ?? recommended
        let model = pack.model(id: chosen)

        let card = buildReportCard(ramble: ramble)
        var applied: [AppliedTechnique] = []

        // Token-efficiency pass: drop throat-clearing and repetition before
        // anything gets added on top.
        let (core, filler) = cleanCore(ramble)
        if !filler.isEmpty {
            let saved = estimator.estimate(ramble, modelID: chosen)
                      - estimator.estimate(core, modelID: chosen)
            let sample = filler.prefix(3).map { "“\($0)”" }.joined(separator: ", ")
            let tail = saved > 0
                ? " — about \(saved) fewer input tokens, identical meaning"
                : " — same meaning, less for the model to wade through"
            applied.append(.init(techniqueID: "clear_direct",
                                 label: "Trimmed filler (\(sample))\(tail)"))
        }
        if hasRetiredPatterns(ramble) {
            applied.append(.init(techniqueID: "retired",
                                 label: "Removed a retired pattern (temperature/prefill/CRITICAL-style language) — current models reject or overreact to it"))
        }

        let prompt = buildPrompt(core: core, ramble: ramble, task: task, model: model,
                                 playbook: playbook, applied: &applied, card: card)
        let schema = shouldEmitSchema(task) ? jsonSchema(for: task) : nil
        if schema != nil {
            applied.append(.init(techniqueID: "structured_mode",
                                 label: "Structured-output mode: attached a JSON schema so results come back machine-readable"))
        }
        if learnedShift, overrideModelID == nil {
            applied.append(.init(techniqueID: "adaptive_defaults",
                                 label: "Recommended \(model?.shortName ?? chosen) because that's what you keep choosing for \(task.label.lowercased()) work — tap any chip to override"))
        }

        var result = CoachResult(
            ramble: ramble, taskType: task.rawValue,
            recommendedModelID: recommended, chosenModelID: chosen,
            rewrittenPrompt: prompt, techniquesApplied: applied,
            reportCard: card, structuredSchema: schema
        )

        // Learned: this user sharpens nearly every prompt of this kind, so
        // hand them the tagged structure instead of a button to press.
        if learning.autoSharpenTasks.contains(task.rawValue) {
            result = sharpen(result, automatic: true)
        }

        result.tokenReport = buildTokenReport(ramble: ramble, core: core,
                                              prompt: result.rewrittenPrompt,
                                              model: model, filler: filler)
        return result
    }

    // MARK: Token accounting

    private func buildTokenReport(ramble: String, core: String, prompt: String,
                                  model: ModelProfile?, filler: [String]) -> TokenReport? {
        guard estimator.isAvailable else { return nil }
        let id = model?.id
        let promptTokens = estimator.estimate(prompt, modelID: id)
        // Priced against the most expensive model in the pack so the
        // recommender's saving is shown, not asserted. Each model is
        // tokenized with its own multiplier.
        let priciest = pack.models.max { $0.priceInPerMtok < $1.priceInPerMtok }
        let priciestTokens = estimator.estimate(prompt, modelID: priciest?.id)
        return TokenReport(
            modelID: id ?? "",
            rambleTokens: estimator.estimate(ramble, modelID: id),
            cleanedTokens: estimator.estimate(core, modelID: id),
            promptTokens: promptTokens,
            fillerRemoved: filler,
            inputCostUSD: estimator.inputCost(tokens: promptTokens, model: model),
            costOnPriciestUSD: estimator.inputCost(tokens: priciestTokens, model: priciest),
            priciestModelName: priciest?.shortName ?? ""
        )
    }

    // MARK: Sharpen (meta-prompting)

    /// Second pass: restructures an already-coached prompt into fully tagged
    /// sections and fills the technique gaps the first pass only flagged.
    ///
    /// This is the `self_correction_chain` technique turned on the prompt
    /// itself — draft, review against the checklist, refine. It stays on
    /// device and deterministic; the optional Test It path (user's own key)
    /// would layer a model-graded pass on top of this.
    func sharpen(_ result: CoachResult, automatic: Bool = false) -> CoachResult {
        let task = TaskType(rawValue: result.taskType) ?? .code
        let model = pack.model(id: result.chosenModelID)
        let suppressed = model?.suppressed ?? []
        var added: [AppliedTechnique] = result.techniquesApplied

        var blocks: [String] = []

        if !suppressed.contains("role"), !muted("role") {
            blocks.append("<role>\n\(roleLine(for: task))\n</role>")
        }

        blocks.append("<context>\n<!-- Who this is for and why it matters. Replace this line. -->\n</context>")

        let (core, filler) = cleanCore(result.ramble)
        blocks.append("<task>\n\(core.isEmpty ? "<!-- your request -->" : core)\n</task>")

        // Examples scaffold — only where output shape actually matters, and
        // only if the original didn't already carry one.
        let shapeMatters: Set<TaskType> = [.classify, .summarize, .email, .writing, .sql]
        if shapeMatters.contains(task), !suppressed.contains("examples"), !muted("examples"),
           !passed(result.reportCard, "examples") {
            blocks.append("""
            <examples>
              <example>
                <input><!-- a representative input --></input>
                <output><!-- the exact shape you want back --></output>
              </example>
            </examples>
            """)
            added.append(.init(techniqueID: "examples",
                               label: "Sharpened: added an example scaffold — 3–5 examples is the most reliable way to lock output shape"))
        }

        // Explicit scope, if the ramble never bounded the work.
        if !passed(result.reportCard, "explicit_scope"), !muted("scope_constraint") {
            blocks.append("<constraints>\n<!-- What to touch and what to leave alone. -->\n</constraints>")
            added.append(.init(techniqueID: "scope_constraint",
                               label: "Sharpened: added a constraints block — unbounded scope is the most common cause of unwanted changes"))
        }

        blocks.append("<success_criteria>\nDone means: \(defaultDoneMeans(task)).\n</success_criteria>")

        for line in model?.extras ?? [] { blocks.append(line) }

        if let model, model.apiFacts?.supportsEffort ?? false, let effort = model.defaultEffort {
            blocks.append("Suggested setting: effort \(effort)\(thinkingNote(for: model)).")
        }

        added.append(.init(
            techniqueID: "meta_prompt",
            label: automatic
                ? "Sharpened up front — you sharpen most \(task.label.lowercased()) prompts, so the tagged sections are already here"
                : "Sharpened: restructured into tagged sections so the model can't confuse instructions, context, and data"))

        var out = result
        out.rewrittenPrompt = blocks.joined(separator: "\n\n")
        out.techniquesApplied = added
        out.isSharpened = true
        // Re-price: the sharpened prompt is a different, usually longer,
        // prompt. A stale estimate is worse than none.
        out.tokenReport = buildTokenReport(ramble: result.ramble, core: core,
                                           prompt: out.rewrittenPrompt,
                                           model: model,
                                           filler: result.tokenReport?.fillerRemoved ?? filler)
        return out
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
            case "xml_structure": return hasPastedBlock(ramble)
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

    private func buildPrompt(core: String, ramble: String, task: TaskType, model: ModelProfile?,
                             playbook: Playbook?, applied: inout [AppliedTechnique],
                             card: ReportCard) -> String {
        var sections: [String] = []
        let ids = Set(playbook?.techniques ?? [])
        let suppressed = model?.suppressed ?? []

        /// A technique fires when the playbook (or a task heuristic) calls for
        /// it AND the target model doesn't suppress it AND the user hasn't
        /// muted it. Suppression is how per-model behavior differences are
        /// honoured — e.g. Opus 5 self-verifies, so `self_check` is suppressed
        /// there. Both suppression and muting only ever subtract, so no
        /// learned preference can re-enable something a model shouldn't see.
        func fires(_ id: String, orTask condition: Bool = false) -> Bool {
            guard !suppressed.contains(id), !muted(id) else { return false }
            return ids.contains(id) || condition
        }

        // 1. Role — domain framing.
        if fires("role", orTask: [.code, .sql, .writing, .design, .debug].contains(task)) {
            sections.append(roleLine(for: task))
            applied.append(.init(techniqueID: "role",
                                 label: "Added a role so the model adopts the right expertise and tone"))
        }

        // 2. Context / why — only prompt for it if the ramble lacked it.
        if fires("add_context", orTask: true), !passed(card, "context_why") {
            sections.append("Context: <one line on who this is for and why it matters — stating the intent measurably sharpens the result, most of all on Fable 5>.")
            applied.append(.init(techniqueID: "add_context",
                                 label: "Prompted you to state the intent — the model connects the task to the goal instead of guessing"))
        }

        // 3. Cleaned core ask — filler trimmed, repetition collapsed, retired
        // patterns stripped (done in `coach`, so the token report can measure
        // the same text the prompt actually carries).
        sections.append("Task: \(core)")

        // 4. Tag pasted data/code if present.
        if hasPastedBlock(ramble), !suppressed.contains("xml_structure"), !muted("xml_structure") {
            applied.append(.init(techniqueID: "xml_structure",
                                 label: "Wrapped your pasted data/code in tags so the model doesn't confuse it with instructions"))
        }

        // 5. Long-context layout.
        if ramble.count > 1_500, !suppressed.contains("long_context"), !muted("long_context") {
            applied.append(.init(techniqueID: "long_context",
                                 label: "Moved your long input to the top and put the question last (+quality on long inputs)"))
        }

        // 6. Success criterion — the single highest-leverage addition.
        if !muted("success_criterion") {
            sections.append("Done means: <the concrete, checkable outcome — e.g. \(defaultDoneMeans(task))>.")
            applied.append(.init(techniqueID: "success_criterion",
                                 label: "Added a success criterion so the model knows exactly what 'done' looks like"))
        }

        // 7. Self-check — correctness-sensitive tasks only, and NEVER on a
        // model that already self-verifies (Opus 5 over-verifies if told to).
        if fires("self_check", orTask: [.code, .sql, .debug].contains(task)) {
            sections.append("Before finishing, verify the result against the success criterion above.")
            applied.append(.init(techniqueID: "self_check",
                                 label: "Added a self-check step — catches errors on code and logic reliably"))
        } else if suppressed.contains("self_check"), [.code, .sql, .debug].contains(task) {
            // Teach the user *why* the usual advice was withheld.
            applied.append(.init(techniqueID: "self_check",
                                 label: "Deliberately did NOT add a 'verify your work' line — \(model?.shortName ?? "this model") self-verifies, and telling it to causes over-verification and wasted tokens"))
        }

        // 8. Scope constraint — for models that widen scope on narrow asks.
        if fires("scope_constraint") {
            applied.append(.init(techniqueID: "scope_constraint",
                                 label: "Added a scope boundary so the model delivers what was asked and no more"))
        }

        // 9. Model-specific instruction lines straight from the pack.
        for line in model?.extras ?? [] where !muted("verbosity") {
            sections.append(line)
        }
        if let model, !model.extras.isEmpty, !muted("verbosity") {
            applied.append(.init(techniqueID: "verbosity",
                                 label: "Added \(model.shortName)-specific lines (conciseness + scope) — its default responses run long"))
        }

        // 10. Effort footer — only for models that actually have an effort
        // ladder. Suggesting one to Haiku 4.5 is an API error.
        if let model, model.apiFacts?.supportsEffort ?? (model.defaultEffort != nil),
           let effort = model.defaultEffort {
            sections.append("Suggested setting: effort \(effort)\(thinkingNote(for: model)).")
        }

        return sections.joined(separator: "\n\n")
    }

    /// Thinking guidance that matches the model's actual default, so the
    /// coach never tells you to set something the API rejects or ignores.
    private func thinkingNote(for model: ModelProfile) -> String {
        switch model.apiFacts?.thinkingWhenOmitted {
        case "on_by_default":  return " (thinking is on by default — no thinking field needed)"
        case "always_on":      return " (thinking is always on — omit the thinking parameter)"
        case "adaptive_on":    return " with adaptive thinking (on by default)"
        case "off":            return " and set thinking to adaptive explicitly (it's off when omitted)"
        default:               return ""
        }
    }

    private func hasPastedBlock(_ s: String) -> Bool {
        if s.contains("```") { return true }
        // Require a plausible tag, not just stray angle brackets in prose.
        return s.range(of: "<[A-Za-z_][A-Za-z0-9_-]*>", options: .regularExpression) != nil
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

    /// Retired prompt-era language that current models reject or overreact to.
    private static let retiredPhrases = ["you must", "You must", "CRITICAL:", "critical:"]

    /// The token-efficiency pass, as a pure function so both `coach` and
    /// `sharpen` measure and emit exactly the same core text.
    ///
    /// Three reductions, none of which change meaning: leading filler,
    /// repeated sentences, and retired directive language. Falls back to the
    /// untouched ramble if the trim would leave nothing behind.
    func cleanCore(_ ramble: String) -> (text: String, filler: [String]) {
        let (deFilled, filler) = estimator.stripFiller(ramble)
        var core = dedupeSentences(deFilled)
        for pattern in Self.retiredPhrases {
            core = core.replacingOccurrences(of: pattern, with: "")
        }
        core = core
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (core.isEmpty ? ramble : core, filler)
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
