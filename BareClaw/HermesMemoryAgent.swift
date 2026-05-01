import Foundation

// MARK: - HermesMemoryAgent
//
// Dedicated memory subagent with three operating modes.
// Fires before/after every companion reply to keep memory consistent.
//
// .message     — save one user+assistant exchange, detect & record emotion
// .recent(n)   — return the last N exchanges + current emotional state
// .fullContext — complete context block: profile + relationship + emotions + facts
// .consolidate — second-pass review of recent exchanges into durable anchors

// MARK: - Mode

enum MemoryAgentMode {
    case message(user: String, assistant: String)
    case recent(count: Int)
    case fullContext
    case consolidateRecent(count: Int)
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
        case .consolidateRecent(let count):
            await consolidateRecentWindow(count: count)
            return nil
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

        // 5. Second-pass consolidation: review the recent window and promote
        // durable user truths so they survive topic shifts and long chats.
        await consolidateRecentWindow(count: 15)
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
        let persona = UserPersona.shared
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

        // 7. Durable memory anchors from the rolling consolidation pass
        let anchors = await stableMemoryAnchors(limit: 14)
        if !anchors.isEmpty {
            sections.append("## Stable Memory Anchors\n" + anchors.map { "• \($0)" }.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Rolling consolidation layer

    private struct ExchangeRecord {
        let user: String
        let assistant: String
    }

    private struct MemoryCandidate {
        let category: String
        let summary: String
        let signal: String
        let importance: Int

        var signature: String {
            "\(category):\(summary)"
                .lowercased()
                .components(separatedBy: .alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "_")
                .prefixString(96)
        }
    }

    private func consolidateRecentWindow(count: Int) async {
        let exchanges = await recentExchangeRecords(count: count)
        guard !exchanges.isEmpty else { return }

        var candidates: [MemoryCandidate] = []
        for exchange in exchanges {
            candidates.append(contentsOf: extractDurableSignals(from: exchange.user))
        }
        candidates.append(contentsOf: extractRepeatedThemes(from: exchanges))

        let uniqueCandidates = dedupeCandidates(candidates)
            .sorted { lhs, rhs in lhs.importance == rhs.importance ? lhs.summary.count > rhs.summary.count : lhs.importance > rhs.importance }
            .prefix(12)

        guard !uniqueCandidates.isEmpty else { return }

        let existing = await memory.entries(forAny: stableMemoryCategories)
        let existingSignatures = Set(existing.compactMap { entry -> String? in
            if let signature = entry.metadata["signature"]?.value as? String {
                return signature
            }
            if let content = entry.content.value as? [String: Any],
               let signature = content["signature"] as? String {
                return signature
            }
            return nil
        })

        var promotedIDs: [UUID] = []
        for candidate in uniqueCandidates where !existingSignatures.contains(candidate.signature) {
            if let id = try? await memory.observe(
                category: candidate.category,
                content: [
                    "summary": candidate.summary,
                    "signal": candidate.signal,
                    "source": "rolling_15_exchange_consolidation",
                    "signature": candidate.signature
                ],
                metadata: [
                    "importance": candidate.importance,
                    "signature": candidate.signature,
                    "source": "rolling_15_exchange_consolidation"
                ]
            ) {
                promotedIDs.append(id)
            }
        }

        if !promotedIDs.isEmpty {
            try? await memory.promoteToLongTerm(promotedIDs)
            _ = try? await memory.persistNow()
        }
    }

    private var stableMemoryCategories: [String] {
        [
            "memory_anchor",
            "user_preference",
            "user_dislike",
            "support_need",
            "user_life_context",
            "conversation_theme",
            "relationship_continuity"
        ]
    }

    private func stableMemoryAnchors(limit: Int) async -> [String] {
        let entries = await memory.entries(forAny: stableMemoryCategories).prefix(limit)
        return entries.compactMap { entry in
            if let content = entry.content.value as? [String: Any],
               let summary = content["summary"] as? String {
                return summary
            }
            return entry.content.value as? String
        }
    }

    private func recentExchangeRecords(count: Int) async -> [ExchangeRecord] {
        let entries = await memory.entries(for: "chat_exchange").prefix(count)
        return entries.compactMap { entry -> ExchangeRecord? in
            guard let dict = entry.content.value as? [String: Any],
                  let user = dict["user"] as? String,
                  let assistant = dict["assistant"] as? String
            else { return nil }
            return ExchangeRecord(user: user, assistant: assistant)
        }
    }

    private func extractDurableSignals(from userText: String) -> [MemoryCandidate] {
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 12 else { return [] }

        var candidates: [MemoryCandidate] = []
        let lower = text.lowercased()

        if lower.containsAny(["remember this", "remember that", "don't forget", "do not forget", "keep this in mind"]) {
            candidates.append(.init(
                category: "memory_anchor",
                summary: "User explicitly wanted this remembered: \(text.prefixString(180))",
                signal: text.prefixString(220),
                importance: 5
            ))
        }

        let phraseRules: [(marker: String, category: String, prefix: String, importance: Int)] = [
            ("my name is", "memory_anchor", "User's name detail:", 5),
            ("call me", "memory_anchor", "User prefers to be called", 5),
            ("i live in", "user_life_context", "User lives in or is connected to", 4),
            ("i work at", "user_life_context", "User works at", 4),
            ("i work as", "user_life_context", "User works as", 4),
            ("my job", "user_life_context", "User's job context:", 4),
            ("i have", "user_life_context", "User has this life context:", 3),
            ("my family", "user_life_context", "User's family context:", 4),
            ("my wife", "user_life_context", "User's wife context:", 4),
            ("my husband", "user_life_context", "User's husband context:", 4),
            ("my girlfriend", "user_life_context", "User's girlfriend context:", 4),
            ("my boyfriend", "user_life_context", "User's boyfriend context:", 4),
            ("my son", "user_life_context", "User's son context:", 4),
            ("my daughter", "user_life_context", "User's daughter context:", 4),
            ("i love", "user_preference", "User loves", 4),
            ("i like", "user_preference", "User likes", 3),
            ("i prefer", "user_preference", "User prefers", 4),
            ("my favorite", "user_preference", "User's favorite:", 4),
            ("i hate", "user_dislike", "User dislikes", 4),
            ("i don't like", "user_dislike", "User does not like", 4),
            ("i need", "support_need", "User needs", 4),
            ("i want", "support_need", "User wants", 3),
            ("i struggle with", "support_need", "User struggles with", 5),
            ("i'm stressed about", "support_need", "User feels stressed about", 5),
            ("i am stressed about", "support_need", "User feels stressed about", 5),
            ("it matters to me", "memory_anchor", "This matters to the user:", 5)
        ]

        for rule in phraseRules {
            guard let fragment = fragment(after: rule.marker, in: lower, original: text) else { continue }
            let cleaned = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count >= 3 else { continue }
            candidates.append(.init(
                category: rule.category,
                summary: "\(rule.prefix) \(cleaned)",
                signal: text.prefixString(220),
                importance: rule.importance
            ))
        }

        return candidates
    }

    private func extractRepeatedThemes(from exchanges: [ExchangeRecord]) -> [MemoryCandidate] {
        let themeRules: [(theme: String, keywords: [String], summary: String)] = [
            ("work", ["work", "job", "boss", "client", "business", "meeting"], "Recent conversations keep returning to work and responsibility."),
            ("stress", ["stress", "stressed", "overwhelmed", "anxious", "pressure", "burnt out"], "Recent conversations show stress/pressure is an active support need."),
            ("relationships", ["wife", "husband", "girlfriend", "boyfriend", "partner", "dating", "relationship"], "Recent conversations keep returning to close relationships."),
            ("family", ["family", "mom", "mother", "dad", "father", "son", "daughter", "kid"], "Recent conversations keep returning to family context."),
            ("music", ["song", "music", "playlist", "artist", "album", "vibe"], "Music is becoming part of the user's emotional profile."),
            ("dreams", ["dream", "dreamed", "nightmare", "sleep"], "Dreams/sleep have been part of recent emotional context."),
            ("health", ["health", "doctor", "pain", "sick", "therapy", "medical"], "Health or body state has been part of recent context."),
            ("app_feedback", ["bug", "broken", "fix", "voice", "robotic", "memory", "forgot"], "The user has been actively shaping how the companion/app should behave.")
        ]

        let combined = exchanges.map(\.user).joined(separator: " ").lowercased()
        var candidates: [MemoryCandidate] = []
        for rule in themeRules {
            let hits = rule.keywords.reduce(0) { count, keyword in
                count + combined.components(separatedBy: keyword).count - 1
            }
            guard hits >= 2 else { continue }
            candidates.append(.init(
                category: "conversation_theme",
                summary: rule.summary,
                signal: rule.theme,
                importance: min(5, 2 + hits)
            ))
        }
        return candidates
    }

    private func fragment(after marker: String, in lower: String, original: String) -> String? {
        guard let range = lower.range(of: marker) else { return nil }
        let startOffset = lower.distance(from: lower.startIndex, to: range.upperBound)
        let originalStart = original.index(original.startIndex, offsetBy: startOffset)
        let suffix = String(original[originalStart...])
        let stopChars = CharacterSet(charactersIn: ".!?\n")
        let fragment = suffix.components(separatedBy: stopChars).first ?? suffix
        return fragment.prefixString(140).trimmingCharacters(in: CharacterSet(charactersIn: " ,:-"))
    }

    private func dedupeCandidates(_ candidates: [MemoryCandidate]) -> [MemoryCandidate] {
        var seen: Set<String> = []
        var output: [MemoryCandidate] = []
        for candidate in candidates {
            guard !seen.contains(candidate.signature) else { continue }
            seen.insert(candidate.signature)
            output.append(candidate)
        }
        return output
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

    func prefixString(_ maxLength: Int) -> String {
        String(prefix(maxLength))
    }
}
