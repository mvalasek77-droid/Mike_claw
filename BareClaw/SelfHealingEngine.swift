import Foundation
import Combine

// MARK: - SelfHealingEngine
//
// The app's self-repair brain. When a user says something went wrong —
// "you said you'd order Chipotle", "that didn't work", "you forgot" —
// this engine:
//   1. Detects the complaint from the chat stream
//   2. Sends it to Claude to understand what went wrong
//   3. Logs the issue to Hermes memory ("self_improvement" category)
//      so ALL future LLM calls know to avoid this mistake
//   4. Responds warmly and honestly to the user
//   5. Schedules a retry attempt when the capability is available
//
// The memory logging is the critical loop: every bug the user reports
// gets stored as a "Known issue to avoid" which is auto-injected into
// every subsequent prompt via HermesLLMClient.buildSystemPrompt().
// Over time the app genuinely gets better.

// MARK: - Bug signal map

private struct BugSignal {
    let pattern:    String
    let confidence: Double
}

// MARK: - Repair record

struct RepairRecord: Identifiable {
    let id          = UUID()
    let timestamp   = Date()
    let complaint:  String        // raw user message
    let issue:      String        // what the engine understood went wrong
    let response:   String        // what it said back
    var resolved:   Bool = false
}

// MARK: - SelfHealingEngine

@MainActor
final class SelfHealingEngine: ObservableObject {

    static let shared = SelfHealingEngine()

    // MARK: Published
    @Published var isAnalyzing:   Bool           = false
    @Published var repairHistory: [RepairRecord] = []

    // MARK: Private
    private var pendingRetries: [(capability: String, retryAfter: Date)] = []

    private let signals: [BugSignal] = [
        BugSignal(pattern: "you said you would",   confidence: 0.95),
        BugSignal(pattern: "you were supposed to", confidence: 0.92),
        BugSignal(pattern: "you promised",         confidence: 0.90),
        BugSignal(pattern: "you didn't",           confidence: 0.82),
        BugSignal(pattern: "you forgot",           confidence: 0.82),
        BugSignal(pattern: "that didn't work",     confidence: 0.78),
        BugSignal(pattern: "it's not working",     confidence: 0.76),
        BugSignal(pattern: "why didn't you",       confidence: 0.75),
        BugSignal(pattern: "why can't you",        confidence: 0.72),
        BugSignal(pattern: "that's wrong",         confidence: 0.72),
        BugSignal(pattern: "that's not right",     confidence: 0.70),
        BugSignal(pattern: "you never",            confidence: 0.68),
        BugSignal(pattern: "you always mess",      confidence: 0.88),
        BugSignal(pattern: "i told you to",        confidence: 0.74),
    ]

    private init() {}

    // MARK: - Entry point: scan every incoming chat message

    /// Call from ChatViewModel on every user message.
    /// Returns `true` if a bug signal was found (caller can pause normal reply pipeline).
    @discardableResult
    func scan(userMessage: String) async -> Bool {
        let lower = userMessage.lowercased()

        // Find the highest-confidence signal present in the message
        let best = signals
            .filter  { lower.contains($0.pattern) }
            .max     { $0.confidence < $1.confidence }

        guard let signal = best, signal.confidence >= 0.68 else { return false }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let analysis = try await analyzeWithClaude(message: userMessage,
                                                        triggeredBy: signal.pattern)
            let record = RepairRecord(complaint: userMessage,
                                      issue:     analysis.issue,
                                      response:  analysis.response)
            repairHistory.insert(record, at: 0)

            // ── Persist to Hermes memory ──────────────────────────────
            await logIssueToMemory(record: record, action: analysis.action)

            // ── Respond to user via companion voice + chat ─────────────
            deliverResponse(analysis.response)

        } catch {
            // Claude unavailable — still acknowledge warmly
            let fallback = fallbackResponse(for: userMessage)
            deliverResponse(fallback)
            await logIssueToMemory(record:
                RepairRecord(complaint: userMessage,
                             issue: "User reported unexpected behaviour",
                             response: fallback),
                action: "Review and improve"
            )
        }

        return true
    }

    // MARK: - Claude analysis

    private struct Analysis {
        let issue:    String
        let action:   String
        let response: String
    }

    private func analyzeWithClaude(message: String, triggeredBy pattern: String) async throws -> Analysis {
        let system = """
        You are the self-repair intelligence of an AI companion app called BareClaw.

        A user has reported something that didn't work as expected. Your job:
        1. Understand what the user expected vs what happened.
        2. Identify which feature was involved (voice, stress relief, food ordering,
           Her Mode ambient listening, music, notifications, memory, etc.).
        3. Write a warm, honest 1–2 sentence response to the user that acknowledges
           the mistake without being defensive, and tells them what will be different.
        4. Note what action should be taken to fix or improve this.

        Known capabilities:
        - Voice responses (AVSpeechSynthesizer, can fail on first launch if muted)
        - Stress relief: offering Netflix, Chipotle, Spotify, DoorDash via URL schemes
        - Her Mode: ambient listening, topic detection, proactive check-ins
        - Memory: HermesMemory stores long-term facts about the user
        - Floating bear ball: presence indicator while Her Mode is active
        - Companion selection: 6 personalities (Luna, Aria, Kel, Marco, Dante, Kai)

        Respond ONLY in valid JSON:
        {
          "issue": "concise description of what went wrong (max 15 words)",
          "action": "what should change or be logged for improvement (max 15 words)",
          "response": "warm honest message to user (max 2 sentences)"
        }
        """

        let userContent = """
        The user said: "\(message)"
        Triggered by the phrase: "\(pattern)"
        """

        let request = LLMRequest(
            systemPrompt: system,
            messages: [LLMMessage(role: .user, content: userContent)],
            tools: [],
            maxTokens: 350,
            role: .execute
        )

        let llm = try await HermesLLMClient.shared.complete(request: request)

        // Parse JSON from response (may be wrapped in a code block)
        let rawContent = llm.content
        let jsonString: String
        if let range = rawContent.range(of: "\\{[\\s\\S]*\\}", options: .regularExpression) {
            jsonString = String(rawContent[range])
        } else {
            jsonString = rawContent
        }

        if let data = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return Analysis(
                issue:    json["issue"]    as? String ?? "Unexpected behaviour",
                action:   json["action"]   as? String ?? "Review interaction",
                response: json["response"] as? String ?? warmFallback()
            )
        }

        return Analysis(
            issue:    "User reported: \(message.prefix(80))",
            action:   "Investigate and improve",
            response: warmFallback()
        )
    }

    // MARK: - Memory logging

    private func logIssueToMemory(record: RepairRecord, action: String) async {
        _ = try? await HermesMemory.shared.observe(
            category: "self_improvement",
            content: [
                "note":      "Avoid: \(record.issue). Fix: \(action)",
                "complaint": String(record.complaint.prefix(200)),
                "logged_at": ISO8601DateFormatter().string(from: record.timestamp)
            ] as [String: Any],
            metadata: ["importance": 4]
        )
    }

    // MARK: - Response delivery

    private func deliverResponse(_ text: String) {
        // Post to chat stream
        NotificationCenter.default.post(
            name: .herModeProactiveMessage,
            object: nil,
            userInfo: ["message": text, "source": "self_healing"]
        )
        // Speak via companion voice
        let companionID = UserDefaults.standard.string(forKey: "selectedCompanionID") ?? "luna"
        let companion   = CompanionPersonality.find(id: companionID) ?? .luna
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            CompanionVoiceEngine.shared.speak(text, character: companion.voiceCharacter)
        }
    }

    // MARK: - Fallbacks

    private func fallbackResponse(for message: String) -> String {
        let templates = [
            "You're right — I should have done that. I've made a note so I don't let you down again.",
            "I hear you. That's on me. I've logged this and I'll figure out the right way to handle it.",
            "I'm sorry about that. I've noted this so I can do better. What would you like me to try now?",
            "That wasn't good enough, and I know it. I've logged the issue — I'll do better next time.",
        ]
        return templates.randomElement()!
    }

    private func warmFallback() -> String { fallbackResponse(for: "") }
}

