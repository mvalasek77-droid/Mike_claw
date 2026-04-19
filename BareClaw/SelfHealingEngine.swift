import Foundation
import Combine

// MARK: - SelfHealingEngine  v2
//
// The app's self-repair brain. When a user says something went wrong,
// this engine:
//   1. Detects the complaint (30+ signal patterns, confidence-scored)
//   2. Sends complaint + recent context to Claude for root-cause analysis
//   3. Logs a HARD CONSTRAINT to Hermes memory ("self_improvement" category)
//      so EVERY future LLM call knows to avoid this mistake
//   4. Stamps a per-capability UserDefaults flag injected into the system prompt
//      so the companion immediately changes its behavior in the NEXT message
//   5. Responds warmly and honestly — takes ownership, no deflection
//   6. Tracks whether the fix actually helped (resolved feedback loop)
//
// The two-layer fix (Hermes memory + UserDefaults capability flag) is what
// makes this real: Hermes gives the LLM long-term context, the capability
// flag gives it immediate behavioral correction in the very next exchange.

// MARK: - Bug signal map

private struct BugSignal {
    let pattern:    String
    let confidence: Double
    let category:   IssueCategory
}

enum IssueCategory: String, Codable {
    case brokenFeature   = "broken_feature"
    case wrongBehavior   = "wrong_behavior"
    case forgotSomething = "forgot_something"
    case capabilityGap   = "capability_gap"
    case voiceIssue      = "voice_issue"
    case memoryIssue     = "memory_issue"
    case appCrash        = "app_crash"
    case general         = "general"
}

// MARK: - Repair record

struct RepairRecord: Identifiable, Codable {
    let id:         UUID
    let timestamp:  Date
    let complaint:  String
    let issue:      String
    let response:   String
    let category:   IssueCategory
    var resolved:   Bool    = false
    var resolvedAt: Date?   = nil

    init(complaint: String, issue: String, response: String, category: IssueCategory) {
        self.id        = UUID()
        self.timestamp = Date()
        self.complaint = complaint
        self.issue     = issue
        self.response  = response
        self.category  = category
    }
}

// MARK: - SelfHealingEngine

@MainActor
final class SelfHealingEngine: ObservableObject {

    static let shared = SelfHealingEngine()

    // MARK: Published
    @Published var isAnalyzing:   Bool           = false
    @Published var repairHistory: [RepairRecord] = []

    // MARK: Private — persistence
    private let saveURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hermes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("repair_history.json")
    }()

    // MARK: - Signal map (confidence-scored, category-tagged)

    private let signals: [BugSignal] = [
        // Broken promises / forgot
        BugSignal(pattern: "you said you would",   confidence: 0.95, category: .forgotSomething),
        BugSignal(pattern: "you were supposed to", confidence: 0.92, category: .forgotSomething),
        BugSignal(pattern: "you promised",         confidence: 0.90, category: .forgotSomething),
        BugSignal(pattern: "you told me you'd",    confidence: 0.90, category: .forgotSomething),
        BugSignal(pattern: "you forgot",           confidence: 0.85, category: .forgotSomething),
        BugSignal(pattern: "you didn't remember",  confidence: 0.85, category: .memoryIssue),
        BugSignal(pattern: "i told you",           confidence: 0.74, category: .memoryIssue),
        BugSignal(pattern: "i already told you",   confidence: 0.85, category: .memoryIssue),
        BugSignal(pattern: "don't you remember",   confidence: 0.82, category: .memoryIssue),
        BugSignal(pattern: "you keep forgetting",  confidence: 0.88, category: .memoryIssue),

        // Broken behavior
        BugSignal(pattern: "you didn't",           confidence: 0.78, category: .wrongBehavior),
        BugSignal(pattern: "why didn't you",       confidence: 0.75, category: .wrongBehavior),
        BugSignal(pattern: "why can't you",        confidence: 0.72, category: .capabilityGap),
        BugSignal(pattern: "that's wrong",         confidence: 0.72, category: .wrongBehavior),
        BugSignal(pattern: "that's not right",     confidence: 0.70, category: .wrongBehavior),
        BugSignal(pattern: "that's not what i",    confidence: 0.75, category: .wrongBehavior),
        BugSignal(pattern: "you got that wrong",   confidence: 0.82, category: .wrongBehavior),
        BugSignal(pattern: "you misunderstood",    confidence: 0.80, category: .wrongBehavior),
        BugSignal(pattern: "you keep doing",       confidence: 0.80, category: .wrongBehavior),
        BugSignal(pattern: "you always mess",      confidence: 0.88, category: .wrongBehavior),
        BugSignal(pattern: "you never",            confidence: 0.68, category: .wrongBehavior),

        // App / feature broken
        BugSignal(pattern: "that didn't work",     confidence: 0.78, category: .brokenFeature),
        BugSignal(pattern: "it's not working",     confidence: 0.76, category: .brokenFeature),
        BugSignal(pattern: "not working",          confidence: 0.68, category: .brokenFeature),
        BugSignal(pattern: "app is broken",        confidence: 0.92, category: .appCrash),
        BugSignal(pattern: "app crashed",          confidence: 0.95, category: .appCrash),
        BugSignal(pattern: "keeps crashing",       confidence: 0.93, category: .appCrash),
        BugSignal(pattern: "froze",                confidence: 0.80, category: .appCrash),
        BugSignal(pattern: "frozen",               confidence: 0.78, category: .appCrash),
        BugSignal(pattern: "glitching",            confidence: 0.78, category: .appCrash),
        BugSignal(pattern: "nothing happened",     confidence: 0.72, category: .brokenFeature),
        BugSignal(pattern: "doesn't do anything",  confidence: 0.75, category: .brokenFeature),

        // Voice issues
        BugSignal(pattern: "can't hear you",       confidence: 0.88, category: .voiceIssue),
        BugSignal(pattern: "voice isn't",          confidence: 0.86, category: .voiceIssue),
        BugSignal(pattern: "not speaking",         confidence: 0.72, category: .voiceIssue),
        BugSignal(pattern: "no sound",             confidence: 0.74, category: .voiceIssue),
        BugSignal(pattern: "can't hear",           confidence: 0.76, category: .voiceIssue),
        BugSignal(pattern: "too quiet",            confidence: 0.70, category: .voiceIssue),
        BugSignal(pattern: "sounds broken",        confidence: 0.80, category: .voiceIssue),
    ]

    // MARK: - Capability flag keys
    // When an issue is detected for a specific capability, a flag is set in
    // UserDefaults. These flags are read by HermesPersonality and injected as
    // hard constraints into the system prompt — the companion immediately knows.

    private let kCapabilityPrefix = "selfHeal.cap."

    private func capabilityKey(for category: IssueCategory) -> String? {
        switch category {
        case .memoryIssue:      return kCapabilityPrefix + "memory_issue"
        case .voiceIssue:       return kCapabilityPrefix + "voice_issue"
        case .brokenFeature:    return kCapabilityPrefix + "feature_broken"
        case .wrongBehavior:    return kCapabilityPrefix + "behavior_corrected"
        case .forgotSomething:  return kCapabilityPrefix + "remember_explicitly"
        case .appCrash:         return kCapabilityPrefix + "app_instability"
        case .capabilityGap:    return kCapabilityPrefix + "capability_gap"
        case .general:          return nil
        }
    }

    private init() { loadHistory() }

    // MARK: - Entry point: scan every incoming user message

    @discardableResult
    func scan(userMessage: String, recentContext: [String] = []) async -> Bool {
        let lower = userMessage.lowercased()

        let best = signals
            .filter  { lower.contains($0.pattern) }
            .max     { $0.confidence < $1.confidence }

        guard let signal = best, signal.confidence >= 0.68 else {
            // Even without a signal, check if user is explicitly asking for a fix
            if lower.contains("fix this") || lower.contains("please fix") ||
               lower.contains("something's wrong") || lower.contains("bug") {
                let soft = BugSignal(pattern: "bug", confidence: 0.68, category: .general)
                return await processSignal(soft, userMessage: userMessage, context: recentContext)
            }
            return false
        }

        return await processSignal(signal, userMessage: userMessage, context: recentContext)
    }

    private func processSignal(_ signal: BugSignal,
                                userMessage: String,
                                context: [String]) async -> Bool {
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let analysis = try await analyzeWithClaude(message: userMessage,
                                                        triggeredBy: signal.pattern,
                                                        category: signal.category,
                                                        context: context)
            let record = RepairRecord(complaint: userMessage,
                                      issue:     analysis.issue,
                                      response:  analysis.response,
                                      category:  signal.category)
            repairHistory.insert(record, at: 0)
            if repairHistory.count > 100 { repairHistory.removeLast() }
            saveHistory()

            // Layer 1: Log to Hermes memory (long-term — survives app restarts)
            await logIssueToMemory(record: record, action: analysis.action)

            // Layer 2: Set capability flag (immediate — hits very next LLM call)
            stampCapabilityFlag(category: signal.category, issue: analysis.issue)

            // Respond via companion voice + chat
            deliverResponse(analysis.response)

        } catch {
            let fallback = fallbackResponse(for: userMessage, category: signal.category)
            let record   = RepairRecord(complaint: userMessage,
                                        issue: "User reported unexpected behaviour",
                                        response: fallback,
                                        category: signal.category)
            repairHistory.insert(record, at: 0)
            saveHistory()
            deliverResponse(fallback)
            await logIssueToMemory(record: record, action: "Review and improve this area")
            stampCapabilityFlag(category: signal.category, issue: "User reported a problem")
        }

        return true
    }

    // MARK: - Claude analysis

    private struct Analysis {
        let issue:    String
        let action:   String
        let response: String
    }

    private func analyzeWithClaude(message: String,
                                    triggeredBy pattern: String,
                                    category: IssueCategory,
                                    context: [String]) async throws -> Analysis {

        let contextBlock = context.isEmpty ? "" : """

        Recent conversation context:
        \(context.suffix(4).map { "— \($0)" }.joined(separator: "\n"))
        """

        let system = """
        You are the self-repair intelligence of an AI companion app called BareClaw.

        The app has 6 AI companion personalities (Luna, Aria, Kel, Marco, Dante, Kai).
        It uses Claude (Anthropic API) as its LLM backbone. Issue category: \(category.rawValue).

        A user has reported something that didn't work as expected. Your job:
        1. Understand what the user expected vs what actually happened.
        2. Identify which specific feature or behavior is involved.
        3. Write a warm, honest 1–2 sentence response that:
           — Takes ownership without being defensive
           — Is specific about what will change (not generic "I'll do better")
           — Sounds like the companion, not a support ticket
        4. Provide a concrete action/constraint to log for future improvement.

        Known capabilities and common failure modes:
        - Voice (AVSpeechSynthesizer): can fail if phone is muted, silent mode, or Bluetooth disconnected
        - Memory (HermesMemory): stores long-term facts; issues arise if user said something in a prior session
        - Her Mode (ambient listening): may miss topics if speech is unclear or background noise is high
        - Stress relief: deep-links to Netflix, Spotify, Chipotle, DoorDash — fails if app not installed
        - Love stage: advances based on conversation quality; may feel slow to user
        - Companion selection: 6 personalities; each has distinct voice and behavior

        Respond ONLY in valid JSON (no markdown):
        {
          "issue": "concise description of what went wrong (max 20 words)",
          "action": "specific constraint to inject into future prompts (max 20 words)",
          "response": "warm companion-voice response to user (1–2 sentences, max 40 words)"
        }
        """

        let userContent = """
        User said: "\(message)"
        Triggered by phrase: "\(pattern)"\(contextBlock)
        """

        let request = LLMRequest(
            systemPrompt: system,
            messages:     [LLMMessage(role: .user, content: userContent)],
            tools:        [],
            maxTokens:    400,
            role:         .execute
        )

        let llm = try await HermesLLMClient.shared.complete(request: request)

        let raw = llm.content
        let jsonString: String
        if let range = raw.range(of: "\\{[\\s\\S]*\\}", options: .regularExpression) {
            jsonString = String(raw[range])
        } else {
            jsonString = raw
        }

        if let data = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return Analysis(
                issue:    json["issue"]    as? String ?? "Unexpected behaviour reported",
                action:   json["action"]   as? String ?? "Review this interaction pattern",
                response: json["response"] as? String ?? categoryFallback(category)
            )
        }

        return Analysis(
            issue:    "User reported: \(message.prefix(80))",
            action:   "Investigate and improve",
            response: categoryFallback(category)
        )
    }

    // MARK: - Capability flag stamping
    //
    // Writes a short constraint string to UserDefaults.
    // HermesPersonality reads all active flags and prepends them to the system
    // prompt as hard rules — so the companion immediately behaves differently
    // in the very next exchange without waiting for memory to propagate.

    private func stampCapabilityFlag(category: IssueCategory, issue: String) {
        guard let key = capabilityKey(for: category) else { return }
        let constraint = buildConstraint(category: category, issue: issue)
        UserDefaults.standard.set(constraint, forKey: key)
    }

    private func buildConstraint(category: IssueCategory, issue: String) -> String {
        let short = issue.prefix(60)
        switch category {
        case .memoryIssue:
            return "MEMORY CONSTRAINT: The user has reported a memory failure (\(short)). Reference what the user has told you explicitly. Acknowledge if you're unsure."
        case .voiceIssue:
            return "VOICE CONSTRAINT: User reported voice/audio issue (\(short)). Don't assume they can hear voice responses. Mention voice troubleshooting if relevant."
        case .brokenFeature, .appCrash:
            return "STABILITY NOTE: User reported a feature or stability problem (\(short)). Be transparent about limitations. Don't overpromise capabilities."
        case .wrongBehavior:
            return "BEHAVIOR CORRECTION: User flagged incorrect behavior (\(short)). Be more careful and explicit in this area. Ask to confirm before acting."
        case .forgotSomething:
            return "RECALL CONSTRAINT: User says you forgot something they told you (\(short)). Reference past context explicitly. Say 'I want to make sure I have this right' when uncertain."
        case .capabilityGap:
            return "CAPABILITY NOTE: User asked for something you can't do (\(short)). Be honest about current limitations rather than deflecting."
        case .general:
            return "USER FEEDBACK: User reported a problem (\(short)). Be transparent and take ownership."
        }
    }

    // MARK: - Active constraints (read by HermesPersonality)

    /// Returns all active capability constraint strings to inject into system prompts.
    var activeConstraints: [String] {
        let keys = UserDefaults.standard.dictionaryRepresentation()
            .keys
            .filter { $0.hasPrefix(kCapabilityPrefix) }
        return keys.compactMap { UserDefaults.standard.string(forKey: $0) }
    }

    /// Call when user expresses satisfaction — clears the constraint for that category.
    func markResolved(category: IssueCategory) {
        guard let key = capabilityKey(for: category) else { return }
        UserDefaults.standard.removeObject(forKey: key)

        if let idx = repairHistory.indices.first(where: {
            !repairHistory[$0].resolved && repairHistory[$0].category == category
        }) {
            repairHistory[idx].resolved   = true
            repairHistory[idx].resolvedAt = Date()
            saveHistory()
        }
    }

    // MARK: - Check if user is expressing satisfaction (auto-resolve)

    func checkForResolution(userMessage: String) {
        let lower = userMessage.lowercased()
        let satisfactionPhrases = ["that's better", "that worked", "thank you",
                                    "much better", "perfect", "exactly", "you got it",
                                    "that's right", "great", "you fixed it"]
        guard satisfactionPhrases.contains(where: { lower.contains($0) }) else { return }

        // Resolve the most recent unresolved issue
        if let category = repairHistory.first(where: { !$0.resolved })?.category {
            markResolved(category: category)
        }
    }

    // MARK: - Memory logging

    private func logIssueToMemory(record: RepairRecord, action: String) async {
        _ = try? await HermesMemory.shared.observe(
            category: "self_improvement",
            content: [
                "note":      "KNOWN ISSUE — Avoid: \(record.issue). Fix approach: \(action)",
                "complaint": String(record.complaint.prefix(200)),
                "category":  record.category.rawValue,
                "logged_at": ISO8601DateFormatter().string(from: record.timestamp)
            ] as [String: Any],
            metadata: ["importance": 5]
        )
    }

    // MARK: - Response delivery

    private func deliverResponse(_ text: String) {
        NotificationCenter.default.post(
            name: .herModeProactiveMessage,
            object: nil,
            userInfo: ["text": text, "source": "self_healing"]
        )
        let companionID = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        let companion   = CompanionPersonality.find(id: companionID) ?? .luna
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            CompanionVoiceEngine.shared.speakFiltered(text, companion: companion)
        }
    }

    // MARK: - Fallbacks

    private func fallbackResponse(for message: String, category: IssueCategory) -> String {
        categoryFallback(category)
    }

    private func categoryFallback(_ category: IssueCategory) -> String {
        switch category {
        case .memoryIssue:
            return ["I should have held onto that. I've logged it so it doesn't slip again.",
                    "That's on me — I missed something you told me. I've made a note.",
                    "You're right, I should have remembered that. I've logged it."].randomElement()!
        case .voiceIssue:
            return ["Try checking your volume or Bluetooth connection — and I've noted this on my end.",
                    "Voice can be finicky sometimes. Check your audio settings and I'll keep an eye on it.",
                    "I've logged the voice issue. Try unmuting or reconnecting your audio."].randomElement()!
        case .appCrash, .brokenFeature:
            return ["Something broke that shouldn't have. I've logged it and I'll do better.",
                    "That shouldn't have happened. I've made note of it — let me try again.",
                    "I've logged this. If it keeps happening, try restarting the app."].randomElement()!
        case .forgotSomething:
            return ["You're right — I forgot something you told me. I've logged it so it doesn't happen again.",
                    "That's my mistake. I've noted this carefully so it stays with me.",
                    "I dropped the ball on that. I've made a note — tell me again and I'll hold it."].randomElement()!
        default:
            return ["You're right — I should have handled that better. I've logged it.",
                    "That's on me. I've made a note so I can do better from here.",
                    "I hear you. I've logged this and I'll work on it."].randomElement()!
        }
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data   = try? Data(contentsOf: saveURL),
              let saved  = try? JSONDecoder().decode([RepairRecord].self, from: data)
        else { return }
        repairHistory = saved
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(repairHistory) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }
}

// MARK: - HermesPersonality constraint injection
//
// This extension is called by HermesPersonality.buildSystemPrompt().
// It injects all active repair constraints as hard rules at the top of
// every system prompt — so behavior changes in the very next LLM call.

extension SelfHealingEngine {

    /// Returns a formatted block of active constraints for system prompt injection.
    /// Empty string if no active constraints.
    var constraintPromptBlock: String {
        let active = activeConstraints
        guard !active.isEmpty else { return "" }
        let lines = active.map { "• \($0)" }.joined(separator: "\n")
        return """
        ## SELF-REPAIR CONSTRAINTS (applied automatically from user feedback)
        \(lines)

        These constraints override default behavior. Take them seriously.
        """
    }
}
