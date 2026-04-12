import Foundation

// MARK: - HermesSuggestion

struct HermesSuggestion: Identifiable {
    let id: UUID
    let title: String
    let body: String
    let category: SuggestionCategory
    let confidence: Double   // 0.0–1.0
    let createdAt: Date
    /// Stable key used for deduplication across evaluations.
    let dedupeKey: String

    enum SuggestionCategory: String {
        case reminder       // "Pick up where you left off?"
        case caution        // "That tool keeps failing."
        case insight        // "While you were away, I noticed…"
        case encouragement  // "You're on a roll today."
    }
}

// MARK: - HermesProactiveEngine
//
// Always-on engine that surfaces friendly, context-aware suggestions.
//
// Improvements over v1:
// - Removed unused `import Combine`
// - Suggestion deduplication: same dedupe key won't surface twice in the same session
// - Smarter interrupted-work detection: checks session gap (> 30 min since last msg),
//   not a fragile 120 s window
// - `inout [HermesSuggestion]` helpers replaced with returning arrays to avoid
//   async+inout complexity

actor HermesProactiveEngine {
    static let shared = HermesProactiveEngine()

    private let memory = HermesMemory.shared
    private var cachedSuggestions: [HermesSuggestion] = []
    private var lastEvaluated: Date = .distantPast

    /// Suggestion dedupe keys seen since app launch (reset on cold start only).
    private var seenDedupeKeys: Set<String> = []

    private let minEvalInterval: TimeInterval = 60

    private init() {}

    // MARK: - Public API

    func currentSuggestions() async -> [HermesSuggestion] {
        if Date().timeIntervalSince(lastEvaluated) > minEvalInterval {
            await evaluate()
        }
        return cachedSuggestions
    }

    func refresh() async {
        await evaluate()
    }

    // MARK: - Evaluation

    private func evaluate() async {
        lastEvaluated = Date()

        var candidates: [HermesSuggestion] = []
        candidates += await checkUnfinishedWork()
        candidates += await checkRepeatedFailures()
        candidates += await checkDreamInsights()
        candidates += await checkEncouragement()

        // Deduplicate: skip any suggestion whose key was already shown this session
        let fresh = candidates.filter { !seenDedupeKeys.contains($0.dedupeKey) }

        // Top 5 by confidence
        let top = fresh.sorted { $0.confidence > $1.confidence }.prefix(5).map { $0 }

        // Record shown keys so they don't repeat
        top.forEach { seenDedupeKeys.insert($0.dedupeKey) }

        cachedSuggestions = top
    }

    // MARK: - Checks

    /// Fires when the last user message has no assistant response AND was sent > 30 min ago,
    /// suggesting the session ended before the answer arrived.
    private func checkUnfinishedWork() async -> [HermesSuggestion] {
        let messages  = await memory.entries(for: "user_message")
        let responses = await memory.entries(for: "assistant_response")
        guard let lastMsg = messages.first else { return [] }   // entries() returns newest first

        let sessionGap: TimeInterval = 30 * 60
        let isOld = Date().timeIntervalSince(lastMsg.timestamp) > sessionGap

        guard isOld else { return [] }

        let hasResponse = responses.contains {
            $0.timestamp > lastMsg.timestamp
        }
        guard !hasResponse else { return [] }

        let topic = (lastMsg.content.value as? [String: Any])?["text"] as? String ?? "your last question"
        let preview = String(topic.prefix(72))

        return [HermesSuggestion(
            id: UUID(),
            title: "Pick up where you left off?",
            body: "Looks like we got cut off. You were asking: \"\(preview)…\" — want to continue that?",
            category: .reminder,
            confidence: 0.85,
            createdAt: Date(),
            dedupeKey: "unfinished_\(lastMsg.id)"
        )]
    }

    private func checkRepeatedFailures() async -> [HermesSuggestion] {
        let execs = await memory.entries(for: "tool_exec")
        let recent = execs.filter { $0.timestamp > Date().addingTimeInterval(-3600) }

        let failures: [String] = recent.compactMap {
            guard let d = $0.content.value as? [String: Any],
                  let ok = d["success"] as? Bool, !ok,
                  let name = d["tool"] as? String else { return nil }
            return name
        }

        let counts = Dictionary(failures.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.compactMap { tool, count -> HermesSuggestion? in
            guard count >= 3 else { return nil }
            return HermesSuggestion(
                id: UUID(),
                title: "'\(tool)' keeps failing",
                body: "That tool has hit an error \(count) times in the last hour. It might need different input or there could be a config issue — want me to take a look?",
                category: .caution,
                confidence: min(0.5 + Double(count) * 0.1, 0.95),
                createdAt: Date(),
                dedupeKey: "failure_\(tool)"
            )
        }
    }

    private func checkDreamInsights() async -> [HermesSuggestion] {
        var out: [HermesSuggestion] = []

        let insights = await memory.entries(for: "dream_insight")
            .filter { $0.timestamp > Date().addingTimeInterval(-86400) }

        for insight in insights.prefix(2) {
            guard let text = (insight.content.value as? [String: Any])?["insight"] as? String,
                  !text.isEmpty else { continue }
            out.append(HermesSuggestion(
                id: UUID(),
                title: "Something I noticed while you were away",
                body: text + " Let me know if you'd like to dive into any of these.",
                category: .insight,
                confidence: 0.70,
                createdAt: insight.timestamp,
                dedupeKey: "insight_\(insight.id)"
            ))
        }

        let improvements = await memory.entries(for: "self_improvement")
            .filter { $0.timestamp > Date().addingTimeInterval(-86400) }

        for imp in improvements.prefix(1) {
            guard let note = (imp.content.value as? [String: Any])?["note"] as? String,
                  !note.isEmpty else { continue }
            out.append(HermesSuggestion(
                id: UUID(),
                title: "Quick heads-up from last night",
                body: note,
                category: .caution,
                confidence: 0.80,
                createdAt: imp.timestamp,
                dedupeKey: "improvement_\(imp.id)"
            ))
        }

        return out
    }

    private func checkEncouragement() async -> [HermesSuggestion] {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayMessages = await memory.entries(for: "user_message")
            .filter { $0.timestamp >= todayStart }

        guard todayMessages.count >= 10 else { return [] }

        // Don't re-encourage today
        let alreadyEncouraged = await memory.entries(for: "encouragement_sent")
            .contains { $0.timestamp >= todayStart }
        guard !alreadyEncouraged else { return [] }

        // Await directly: checkEncouragement is already async, and writing inside
        // a detached Task would allow a second evaluate() to race past the guard
        // before the flag is persisted, causing duplicate encouragement suggestions.
        try? await memory.observe(
            category: "encouragement_sent",
            content: ["count": todayMessages.count],
            metadata: ["importance": 1]
        )

        return [HermesSuggestion(
            id: UUID(),
            title: "You're on a roll today",
            body: "You've sent \(todayMessages.count) messages today — that's a productive session. Remember to take a break when you need one. I'll be here.",
            category: .encouragement,
            confidence: 0.60,
            createdAt: Date(),
            dedupeKey: "encouragement_\(todayStart.timeIntervalSince1970)"
        )]
    }
}

// MARK: - SwiftUI ViewModel

@MainActor
final class HermesViewModel: ObservableObject {
    @Published var suggestions: [HermesSuggestion] = []
    @Published var isLoading = false

    private var refreshTask: Task<Void, Never>?

    func refresh() {
        // Cancel any in-flight refresh before starting a new one
        refreshTask?.cancel()
        isLoading = true
        refreshTask = Task { [weak self] in
            let fresh = await HermesProactiveEngine.shared.currentSuggestions()
            guard !Task.isCancelled, let self else { return }
            self.suggestions = fresh
            self.isLoading = false
        }
    }
}
