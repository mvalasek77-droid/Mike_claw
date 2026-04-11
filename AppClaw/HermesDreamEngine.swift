import Foundation
import BackgroundTasks

// MARK: - HermesDreamEngine
//
// "Dream mode" — runs while the app is backgrounded, targeting ~2 am local time.
//
// Improvements over v1:
// - Batch memory updates: all promotions in one persist call (was N separate calls)
// - Smart 2 am scheduling: aims for the next 2 am local time, not "5 hours from now"
// - Proper English stopword list for topic insight generation
// - Removed unused `dreamLog: [DreamEntry]`
// - `handleDream` no longer captures `self` strongly in nested closure
// - `phase4_selfImprove` scoped to recent 24 h, not all-time

final class HermesDreamEngine {
    static let shared = HermesDreamEngine()

    private let taskIdentifier = "com.openclaw.hermes.dream"
    private let memory = HermesMemory.shared

    private init() {}

    // MARK: - Registration

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { [weak self] task in
            guard let self, let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleDream(task: processingTask)
        }
    }

    /// Call when the app moves to background. Schedules the next dream at ~2 am local.
    func scheduleNextDream() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = nextDreamDate()
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Next occurrence of 2 am local time. If it's already past 2 am today, uses tomorrow.
    private func nextDreamDate() -> Date {
        let cal = Calendar.current
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour = 2
        components.minute = 0
        components.second = 0
        let todayAt2 = cal.date(from: components) ?? Date()
        // If we've passed today's 2 am, aim for tomorrow
        return todayAt2 > Date() ? todayAt2 : todayAt2.addingTimeInterval(86400)
    }

    // MARK: - Dream execution

    private func handleDream(task: BGProcessingTask) {
        let dreamTask = Task { [weak self] in
            guard let self else { return }
            await self.runDreamCycle()
            task.setTaskCompleted(success: true)
            self.scheduleNextDream()
        }
        task.expirationHandler = { dreamTask.cancel() }
    }

    /// Full dream cycle. Also callable manually (e.g., from a Debug/Settings screen).
    @discardableResult
    func runDreamCycle() async -> DreamReport {
        var report = DreamReport(startedAt: Date())

        await phase1_consolidate(&report)
        await phase2_promotePatterns(&report)
        await phase3_generateInsights(&report)
        await phase4_selfImprove(&report)
        await phase5_resolveContradictions(&report)

        report.finishedAt = Date()
        await saveDreamReport(report)
        return report
    }

    // MARK: - Phase 1: Consolidate

    private func phase1_consolidate(_ report: inout DreamReport) async {
        let before = await memory.allEntries().count
        do {
            try await memory.consolidate(importanceThreshold: 2, keepWindow: 7 * 86400)
            let after = await memory.allEntries().count
            report.pruned = max(0, before - after)
            report.phases.append("Pruned \(report.pruned) low-importance entries.")
        } catch {
            report.phases.append("Consolidation error: \(error)")
        }
    }

    // MARK: - Phase 2: Promote patterns (single batch persist)

    private func phase2_promotePatterns(_ report: inout DreamReport) async {
        let all = await memory.allEntries()

        let freq = Dictionary(grouping: all, by: \.category).mapValues(\.count)

        // Collect all mutations first, then write once
        var updated: [MemoryEntry] = []
        var promotedIDs: [UUID] = []

        for entry in all {
            let count = freq[entry.category, default: 0]
            if count > 5 && entry.importance < 4 {
                var e = entry
                e = MemoryEntry(
                    id: e.id, timestamp: e.timestamp, category: e.category,
                    content: e.content.value,
                    metadata: e.metadata.mapValues { $0.value },
                    importance: min(e.importance + 1, 5),
                    tier: e.tier
                )
                updated.append(e)
            }
            // Promote high-importance entries to long-term tier
            if entry.importance >= 4 && entry.tier == .shortTerm {
                promotedIDs.append(entry.id)
            }
        }

        do {
            if !updated.isEmpty  { try await memory.updateBatch(updated) }
            if !promotedIDs.isEmpty { try await memory.promoteToLongTerm(promotedIDs) }
        } catch {
            report.phases.append("Promotion error: \(error)")
        }

        report.promoted = updated.count
        report.phases.append("Promoted \(updated.count) entries; moved \(promotedIDs.count) to long-term.")
    }

    // MARK: - Phase 3: Generate insights

    private static let stopwords: Set<String> = [
        "the","and","for","are","but","not","you","all","can","had","her","was","one",
        "our","out","day","get","has","him","his","how","man","new","now","old","see",
        "two","way","who","boy","did","its","let","put","say","she","too","use","that",
        "with","have","this","will","your","from","they","know","want","been","good",
        "much","some","time","very","when","come","here","just","like","long","make",
        "many","more","only","over","such","take","than","them","well","were","what",
        "also","into","most","other","said","then","there","these","think","those",
        "about","after","being","could","every","going","great","their","where","which",
        "would","should","would","because","through"
    ]

    private func phase3_generateInsights(_ report: inout DreamReport) async {
        let recentMessages = await memory.entries(for: "user_message")
            .prefix(100)
            .compactMap { ($0.content.value as? [String: Any])?["text"] as? String }

        guard !recentMessages.isEmpty else {
            report.phases.append("No recent messages to analyse.")
            return
        }

        let words = recentMessages.joined(separator: " ")
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 3 && !Self.stopwords.contains($0) }

        let freq = Dictionary(words.map { ($0, 1) }, uniquingKeysWith: +)
        let topWords = freq.sorted { $0.value > $1.value }.prefix(8).map(\.key)

        guard !topWords.isEmpty else { return }

        let insight = "Recurring topics in recent conversations: \(topWords.joined(separator: ", "))."
        report.insights.append(insight)
        report.phases.append("Topic insight: \(insight)")

        try? await memory.observe(
            category: "dream_insight",
            content: ["insight": insight, "basedOn": recentMessages.count, "topWords": topWords],
            metadata: ["importance": 4]
        )
    }

    // MARK: - Phase 4: Self-improve

    private func phase4_selfImprove(_ report: inout DreamReport) async {
        // Scope to last 24 h only — all-time error counts are noisy
        let since = Date().addingTimeInterval(-86400)
        let errors = await memory.entries(for: "tool_exec")
            .filter { $0.timestamp >= since }
            .filter {
                guard let d = $0.content.value as? [String: Any],
                      let ok = d["success"] as? Bool else { return false }
                return !ok
            }

        guard errors.count >= 3 else {
            report.phases.append("Self-improvement: no recurring failures in last 24 h.")
            return
        }

        let toolNames = errors.compactMap { ($0.content.value as? [String: Any])?["tool"] as? String }
        let counts = Dictionary(toolNames.map { ($0, 1) }, uniquingKeysWith: +)
        let worst = counts.sorted { $0.value > $1.value }.prefix(2)
            .map { "\($0.key) (\($0.value)x)" }
        let note = "Heads-up: repeated failures in \(worst.joined(separator: ", ")) over the last 24 h. Consider reviewing these tools."

        report.improvements.append(note)
        report.phases.append("Self-improvement note written.")

        try? await memory.observe(
            category: "self_improvement",
            content: ["note": note, "errorCount": errors.count],
            metadata: ["importance": 5]
        )
    }

    // MARK: - Phase 5: Resolve contradictions
    //
    // Looks for entries in the same category where the content directly
    // contradicts a later entry (e.g. two self_improvement notes about the
    // same tool with conflicting advice, or two dream_insights with
    // opposite conclusions).
    //
    // Strategy: when two entries in the same category share the same top
    // keyword AND were written > 1 h apart, keep only the newer one and
    // mark the older as superseded (importance → 1 so it gets pruned next cycle).

    private func phase5_resolveContradictions(_ report: inout DreamReport) async {
        let candidateCategories = ["dream_insight", "self_improvement", "kairos_insight"]
        var resolved = 0

        for category in candidateCategories {
            let entries = await memory.entries(for: category)
            guard entries.count >= 2 else { continue }

            // Group by dominant keyword (first non-stopword word in content text)
            var groups: [String: [MemoryEntry]] = [:]
            for entry in entries {
                let text = (entry.content.value as? [String: Any])?
                    .values.compactMap { $0 as? String }.joined(separator: " ")
                    ?? "\(entry.content.value)"
                if let key = dominantKeyword(text) {
                    groups[key, default: []].append(entry)
                }
            }

            for (_, group) in groups where group.count >= 2 {
                // Sort newest first; demote all but the newest
                let sorted = group.sorted { $0.timestamp > $1.timestamp }
                let toSupersede = sorted.dropFirst()
                    .filter { $0.importance > 1 }

                let superseded: [MemoryEntry] = toSupersede.map { entry in
                    MemoryEntry(
                        id: entry.id, timestamp: entry.timestamp,
                        category: entry.category,
                        content: entry.content.value,
                        metadata: entry.metadata.mapValues(\.value),
                        importance: 1,    // will be pruned next consolidation
                        tier: entry.tier
                    )
                }

                if !superseded.isEmpty {
                    try? await memory.updateBatch(superseded)
                    resolved += superseded.count
                }
            }
        }

        report.resolved = resolved
        report.phases.append(
            resolved > 0
                ? "Contradiction resolution: superseded \(resolved) outdated entries."
                : "Contradiction resolution: no contradictions found."
        )
    }

    private func dominantKeyword(_ text: String) -> String? {
        text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 4 && !Self.stopwords.contains($0) }
            .first
    }

    // MARK: - Persistence

    private func saveDreamReport(_ report: DreamReport) async {
        let duration = report.finishedAt.map { $0.timeIntervalSince(report.startedAt) } ?? 0
        try? await memory.observe(
            category: "dream_report",
            content: [
                "duration_s": Int(duration),
                "pruned": report.pruned,
                "promoted": report.promoted,
                "resolved": report.resolved,
                "insights": report.insights,
                "improvements": report.improvements
            ],
            metadata: ["importance": 4]
        )
    }
}

// MARK: - Models

struct DreamReport {
    let startedAt: Date
    var finishedAt: Date?
    var pruned: Int = 0
    var promoted: Int = 0
    var resolved: Int = 0
    var phases: [String] = []
    var insights: [String] = []
    var improvements: [String] = []
}
