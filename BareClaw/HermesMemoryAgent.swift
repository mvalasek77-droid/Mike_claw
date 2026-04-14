import Foundation

// MARK: - HermesMemoryAgent
//
// Dedicated memory subagent with three operating modes.
// Fires before/after every companion reply to keep memory consistent.
//
// .message     — save one user+assistant exchange, detect & record emotion
// .recent(n)   — return the last N exchanges + current emotional state
// .fullContext — complete context block: profile + relationship + emotions + facts

// MARK: - Mode

enum MemoryAgentMode {
    case message(user: String, assistant: String)
    case recent(count: Int)
    case fullContext
}

// MARK: - HermesMemoryAgent

actor HermesMemoryAgent {
    static let shared = HermesMemoryAgent()
    private init() {}

    private let memory   = HermesMemory.shared
    private let learning = HerLearningEngine.shared

    // MARK: - Entry point

    /// Run the agent in the given mode.
    /// Returns a context string for `.recent` and `.fullContext` modes; nil for `.message`.
    @discardableResult
    func run(_ mode: MemoryAgentMode) async -> String? {
        switch mode {
        case .message(let user, let assistant):
            await handleMessageExchange(user: user, assistant: assistant)
            return nil
        case .recent(let count):
            return await buildRecentContext(count: count)
        case .fullContext:
            return await buildFullContext()
        }
    }

    // MARK: - .message mode

    private func handleMessageExchange(user: String, assistant: String) async {
        // 1. Detect emotion from user message
        let emotion = detectEmotion(from: user)

        // 2. Persist detected emotion to LearningEngine
        if emotion != .neutral {
            await learning.updateCurrentEmotion(emotion)
            _ = try? await memory.observe(
                category: "emotion_state",
                content: ["emotion": emotion.rawValue,
                          "trigger": String(user.prefix(120))],
                metadata: ["importance": 3]
            )
        }

        // 3. Save the exchange itself
        _ = try? await memory.observe(
            category: "chat_exchange",
            content: ["user": user, "assistant": String(assistant.prefix(400))],
            metadata: ["importance": 2]
        )

        // 4. Flush to disk immediately so state survives a crash
        _ = try? await memory.persistNow()
    }

    // MARK: - .recent mode

    private func buildRecentContext(count: Int) async -> String {
        // entries(for:) returns newest-first; .prefix gives the most recent `count`
        let entries = await memory.entries(for: "chat_exchange").prefix(count)
        guard !entries.isEmpty else { return "No recent messages." }

        let emotion = await learning.currentEmotionTag
        var lines = entries.compactMap { entry -> String? in
            guard let dict = entry.content.value as? [String: Any],
                  let user = dict["user"] as? String,
                  let assistant = dict["assistant"] as? String
            else { return nil }
            return "User: \(user)\nAssistant: \(assistant)"
        }.joined(separator: "\n---\n")

        if emotion != .neutral {
            lines += "\n\nCurrent emotional state: \(emotion.rawValue)"
        }
        return lines
    }

    // MARK: - .fullContext mode

    private func buildFullContext() async -> String {
        let persona = UserPersona.load()
        var sections: [String] = []

        // 1. User profile
        var profileLines: [String] = []
        if !persona.userName.isEmpty {
            profileLines.append("Name: \(persona.userName)")
        }
        profileLines.append("Companion: \(persona.selectedCompanion.name)")
        profileLines.append("Relationship mode: \(persona.relationshipMode.label)")
        profileLines.append("Style: \(persona.style.label)")
        if !persona.interests.isEmpty {
            let list = persona.interests.map { "\($0.emoji) \($0.label)" }.joined(separator: ", ")
            profileLines.append("Interests: \(list)")
        }
        sections.append("## User Profile\n" + profileLines.joined(separator: "\n"))

        // 2. Relationship state
        let stage     = await learning.intimacyStage
        let score     = await learning.intimacyScore
        let totalMsgs = await learning.totalMessages
        sections.append("""
        ## Relationship
        Stage: \(stage.label) (\(Int(score))/100)
        Total messages: \(totalMsgs)
        """)

        // 3. Current emotion
        let emotion = await learning.currentEmotionTag
        if emotion != .neutral {
            sections.append("## Emotional State\nCurrent: \(emotion.rawValue)")
        }

        // 4. Emotional arc (last 5 emotion records) — newest-first, so .prefix(5)
        let emotionEntries = await memory.entries(for: "emotion_state").prefix(5)
        if !emotionEntries.isEmpty {
            let arc = emotionEntries.compactMap { entry -> String? in
                (entry.content.value as? [String: Any])?["emotion"] as? String
            }.joined(separator: " → ")
            if !arc.isEmpty {
                sections.append("## Emotional Arc\n\(arc)")
            }
        }

        // 5. Recent conversation (last 10 exchanges)
        let recentContext = await buildRecentContext(count: 10)
        sections.append("## Recent Conversation\n\(recentContext)")

        // 6. Learned facts
        let learnedFacts = persona.learnedFacts
        if !learnedFacts.isEmpty {
            let facts = learnedFacts.map { "• \($0.key): \($0.value)" }.joined(separator: "\n")
            sections.append("## Learned Facts\n\(facts)")
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Emotion detection

    private func detectEmotion(from text: String) -> EmotionTag {
        let lower = text.lowercased()
        if lower.containsAny(["anxious", "stressed", "overwhelmed", "nervous", "worried"]) {
            return .anxious
        }
        if lower.containsAny(["sad", "down", "depressed", "lonely", "hurt", "crying"]) {
            return .sad
        }
        if lower.containsAny(["happy", "excited", "amazing", "great", "thrilled", "love it"]) {
            return .joyful
        }
        if lower.containsAny(["angry", "frustrated", "annoyed", "pissed", "furious"]) {
            return .frustrated
        }
        if lower.containsAny(["tired", "exhausted", "burnt out", "drained", "sleepy"]) {
            return .tired
        }
        return .neutral
    }
}

// MARK: - String helper (local — EmotionTag.promptHint uses the one in HerLearningEngine)

private extension String {
    func containsAny(_ words: [String]) -> Bool {
        let lower = self.lowercased()
        return words.contains { lower.contains($0) }
    }
}
