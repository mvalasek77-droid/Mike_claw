import Foundation
import BackgroundTasks

// MARK: - HermesDreamEngine
//
// "Dream mode" — runs while the app is backgrounded (typically at night).
// It consolidates memory, promotes important patterns, prunes noise,
// and writes a brief self-improvement log so Hermes wakes up smarter.
//
// Register the BGProcessingTask identifier "com.openclaw.hermes.dream"
// in Info.plist under BGTaskSchedulerPermittedIdentifiers.

final class HermesDreamEngine {
    static let shared = HermesDreamEngine()

    private let taskIdentifier = "com.openclaw.hermes.dream"
    private let memory = HermesMemory.shared
    private var dreamLog: [DreamEntry] = []

    // How many hours of inactivity before dreaming starts
    private let dreamAfterHours: Double = 5

    private init() {}

    // MARK: - Registration (call from AppDelegate / @main)

    /// Register the background processing task. Call once at app launch.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            self.handleDream(task: processingTask)
        }
    }

    /// Schedule the next dream session. Call when the app moves to background.
    func scheduleNextDream() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: dreamAfterHours * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Dream execution

    private func handleDream(task: BGProcessingTask) {
        let dreamTask = Task {
            await self.runDreamCycle()
            task.setTaskCompleted(success: true)
            self.scheduleNextDream()     // schedule the next night
        }
        task.expirationHandler = { dreamTask.cancel() }
    }

    /// Full dream cycle. Can also be triggered manually (e.g., from Settings for testing).
    @discardableResult
    func runDreamCycle() async -> DreamReport {
        let start = Date()
        var report = DreamReport(startedAt: start)

        await phase1_consolidate(&report)
        await phase2_promotePatterns(&report)
        await phase3_generateInsights(&report)
        await phase4_selfImprove(&report)

        report.finishedAt = Date()
        await saveDreamReport(report)
        return report
    }

    // MARK: - Phase 1: Consolidate (prune old/low-value memories)

    private func phase1_consolidate(_ report: inout DreamReport) async {
        let before = await memory.recentEntries(limit: 10_000).count
        do {
            try await memory.consolidate(importanceThreshold: 2, keepWindow: 7 * 86400)
            let after = await memory.recentEntries(limit: 10_000).count
            report.pruned = max(0, before - after)
            report.phases.append("Pruned \(report.pruned) low-importance entries.")
        } catch {
            report.phases.append("Consolidation error: \(error)")
        }
    }

    // MARK: - Phase 2: Promote patterns (bump importance of recurring content)

    private func phase2_promotePatterns(_ report: inout DreamReport) async {
        let all = await memory.recentEntries(limit: 5_000)
        var promoted = 0

        // Count category frequency
        let freq = Dictionary(grouping: all, by: \.category)
            .mapValues(\.count)

        for entry in all {
            let count = freq[entry.category, default: 0]
            // If a category appears > 5 times, treat it as a recurring pattern → promote
            if count > 5 && entry.importance < 4 {
                var updated = entry
                updated = MemoryEntry(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    category: entry.category,
                    content: entry.content.value,
                    metadata: entry.metadata.mapValues(\.value),
                    importance: min(entry.importance + 1, 5)
                )
                try? await memory.update(updated)
                promoted += 1
            }
        }
        report.promoted = promoted
        report.phases.append("Promoted \(promoted) recurring-pattern entries.")
    }

    // MARK: - Phase 3: Generate insights (summarise recent context)

    private func phase3_generateInsights(_ report: inout DreamReport) async {
        let recentMessages = await memory.entries(for: "user_message")
            .suffix(50)
            .compactMap { $0.content.value as? [String: Any] }
            .compactMap { $0["text"] as? String }

        guard !recentMessages.isEmpty else {
            report.phases.append("No recent messages to analyse.")
            return
        }

        // Build a simple word-frequency insight (on-device, no LLM call needed)
        let words = recentMessages.joined(separator: " ")
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 4 }   // ignore short words
        let freq = Dictionary(words.map { ($0, 1) }, uniquingKeysWith: +)
        let topWords = freq.sorted { $0.value > $1.value }.prefix(5).map(\.key)

        let insight = "Top recurring topics: \(topWords.joined(separator: ", "))."
        report.insights.append(insight)
        report.phases.append("Generated topic insight: \(insight)")

        // Store the insight in memory with high importance
        try? await memory.observe(
            category: "dream_insight",
            content: ["insight": insight, "basedOn": recentMessages.count],
            metadata: ["importance": 4]
        )
    }

    // MARK: - Phase 4: Self-improve (write a clean-up note for next session)

    private func phase4_selfImprove(_ report: inout DreamReport) async {
        // Surface patterns that look like repeated errors → store as a reminder
        let errors = await memory.entries(for: "tool_exec")
            .filter {
                if let d = $0.content.value as? [String: Any], let ok = d["success"] as? Bool {
                    return !ok
                }
                return false
            }

        if errors.count >= 3 {
            let toolNames = errors.compactMap {
                ($0.content.value as? [String: Any])?["tool"] as? String
            }
            let counts = Dictionary(toolNames.map { ($0, 1) }, uniquingKeysWith: +)
            let worst = counts.sorted { $0.value > $1.value }.prefix(2).map { "\($0.key) (\($0.value)x)" }
            let note = "Heads-up: repeated failures in \(worst.joined(separator: ", ")). Consider reviewing these tools."

            report.improvements.append(note)
            try? await memory.observe(
                category: "self_improvement",
                content: ["note": note],
                metadata: ["importance": 5]
            )
        }
        report.phases.append("Self-improvement scan complete.")
    }

    // MARK: - Persistence

    private func saveDreamReport(_ report: DreamReport) async {
        try? await memory.observe(
            category: "dream_report",
            content: [
                "duration_s": report.finishedAt.flatMap { $0.timeIntervalSince(report.startedAt) } ?? 0,
                "pruned": report.pruned,
                "promoted": report.promoted,
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
    var phases: [String] = []
    var insights: [String] = []
    var improvements: [String] = []
}

struct DreamEntry {
    let date: Date
    let summary: String
}
