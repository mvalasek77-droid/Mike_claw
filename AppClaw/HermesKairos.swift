import Foundation

// MARK: - Kairos ("the right time")
//
// Kairos is the always-on background observer.  It watches the user's working
// environment, writes structured observation logs, and waits for a 15-second
// window of inactivity before proposing or taking autonomous action — so it
// never interrupts mid-thought.
//
// Three design contracts:
//   1. 15-Second Budget  — only act after 15 s of detected user inactivity.
//   2. Observation Log   — every environmental scan is recorded before any
//                          action is proposed, creating an audit trail.
//   3. Strict Write Discipline — observations are only committed to persistent
//                          memory AFTER the related action succeeds.  Failed
//                          or speculative data is never stored.

// MARK: - Models

struct KairosObservation {
    let id: UUID
    let timestamp: Date
    let trigger: ObservationTrigger
    let context: [String: Any]   // freeform snapshot of the environment
    let sessionTopic: String?
    let intent: HermesContextTracker.Intent?

    enum ObservationTrigger: String {
        case idleTimeout        // 15 s of inactivity elapsed
        case sessionStart       // app foregrounded
        case sessionEnd         // app backgrounded
        case errorDetected      // tool failure logged
        case patternRecognised  // DreamEngine surfaced an insight
    }
}

struct KairosAction {
    let id: UUID
    let observation: KairosObservation
    let type: ActionType
    let description: String
    let confidence: Double       // 0.0–1.0; only execute if >= threshold
    var outcome: ActionOutcome?

    enum ActionType: String {
        case suggestContext      // surface a suggestion to the UI
        case consolidateMemory   // trigger early mini-dream
        case flagContradiction   // mark conflicting memories for review
        case promoteEntry        // bump importance of a relevant entry
        case logInsight          // write a new dream_insight entry
    }

    enum ActionOutcome {
        case success
        case failure(Error)
        case skipped(reason: String)
    }
}

// MARK: - HermesKairos

actor HermesKairos {
    static let shared = HermesKairos()

    // Dependencies
    private let memory      = HermesMemory.shared
    private let context     = HermesContextTracker.shared
    private let proactive   = HermesProactiveEngine.shared

    // State
    private var isRunning   = false
    private var lastActivity: Date = Date()
    private var observationLog: [KairosObservation] = []
    private var pendingWrites: [(category: String, content: Any, metadata: [String: Any])] = []
    // Bug fix #3: store the loop Task so pause() can cancel it and stop the chain.
    private var loopTask: Task<Void, Never>?

    // Config
    private let idleBudgetSeconds: TimeInterval = 15
    private let minConfidenceToAct: Double = 0.65
    private let maxObservationLogSize = 200

    private init() {}

    // MARK: - Lifecycle

    /// Start the Kairos background loop. Call from AppDelegate / scene activation.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleNextCheck()
    }

    /// Pause Kairos (e.g. when app backgrounds — DreamEngine takes over instead).
    func pause() {
        isRunning = false
        // Bug fix #3: cancel the stored task so the recursive chain terminates.
        loopTask?.cancel()
        loopTask = nil
    }

    /// Signal that the user is active — resets the 15-second idle budget.
    func userDidAct() {
        lastActivity = Date()
    }

    // MARK: - Idle check loop

    private func scheduleNextCheck() {
        // Bug fix #3: store the task so pause() can cancel it.
        loopTask = Task { [weak self] in
            // Poll every 5 s; fire the full observation when idle budget is met
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self, await self.isRunning else { return }
            await self.tick()
            await self.scheduleNextCheck()
        }
    }

    private func tick() async {
        let idle = Date().timeIntervalSince(lastActivity)
        guard idle >= idleBudgetSeconds else { return }

        let obs = await buildObservation(trigger: .idleTimeout)
        observationLog.append(obs)
        trimObservationLog()

        let action = await proposeAction(for: obs)
        await executeIfWarranted(action)
    }

    // MARK: - Observation

    private func buildObservation(trigger: KairosObservation.ObservationTrigger) async -> KairosObservation {
        let topic  = await context.currentTopic()
        let intent = await context.currentIntent()
        let recent = await memory.recentEntries(limit: 5)

        let ctx: [String: Any] = [
            "recentCategories": recent.map(\.category),
            "idleSeconds":      Date().timeIntervalSince(lastActivity),
            "observationCount": observationLog.count
        ]

        return KairosObservation(
            id: UUID(),
            timestamp: Date(),
            trigger: trigger,
            context: ctx,
            sessionTopic: topic,
            intent: intent
        )
    }

    // MARK: - Action proposal

    private func proposeAction(for obs: KairosObservation) async -> KairosAction {
        // Check for tool failures → flag or consolidate
        let recentErrors = await memory.entries(for: "tool_exec")
            .prefix(20)
            .filter {
                guard let d = $0.content.value as? [String: Any],
                      let ok = d["success"] as? Bool else { return false }
                return !ok
            }

        if recentErrors.count >= 3 {
            return KairosAction(
                id: UUID(), observation: obs,
                type: .consolidateMemory,
                description: "Recurring failures detected — trigger early memory consolidation.",
                confidence: 0.80
            )
        }

        // Check if a dream insight exists that hasn't been surfaced yet
        let unseenInsights = await memory.entries(for: "dream_insight")
            .filter { $0.timestamp > Date().addingTimeInterval(-3600) }
        if !unseenInsights.isEmpty {
            return KairosAction(
                id: UUID(), observation: obs,
                type: .suggestContext,
                description: "Unseen dream insight available — refresh proactive suggestions.",
                confidence: 0.72
            )
        }

        // Default: nothing warranted right now
        return KairosAction(
            id: UUID(), observation: obs,
            type: .suggestContext,
            description: "Idle scan complete, no urgent action.",
            confidence: 0.10
        )
    }

    // MARK: - Execution with strict write discipline

    private func executeIfWarranted(_ action: KairosAction) async {
        guard action.confidence >= minConfidenceToAct else {
            recordOutcome(action, .skipped(reason: "Confidence \(action.confidence) below threshold \(minConfidenceToAct)"))
            return
        }

        var result = action
        do {
            try await perform(action)
            // ✅ STRICT WRITE DISCIPLINE: only flush pending writes after success
            try await flushPendingWrites()
            result.outcome = .success
        } catch {
            // ❌ Do NOT write speculative data — discard pending writes
            pendingWrites.removeAll()
            result.outcome = .failure(error)
        }
        recordOutcome(result, result.outcome ?? .skipped(reason: "unknown"))
    }

    private func perform(_ action: KairosAction) async throws {
        switch action.type {
        case .consolidateMemory:
            try await memory.consolidate(importanceThreshold: 2, keepWindow: 7 * 86400)

        case .suggestContext:
            await proactive.refresh()

        case .promoteEntry:
            // Promote the most recently accessed relevant entry
            let recent = await memory.recentEntries(limit: 1)
            if let entry = recent.first {
                try await memory.promoteToLongTerm([entry.id])
            }

        case .logInsight:
            let topic = action.observation.sessionTopic ?? "general"
            // Stage the write — only committed if this action succeeds (flushPendingWrites)
            pendingWrites.append((
                category: "kairos_insight",
                content: ["topic": topic, "trigger": action.observation.trigger.rawValue],
                metadata: ["importance": 3]
            ))

        case .flagContradiction:
            // Surfaced by DreamEngine phase 5; log for review
            pendingWrites.append((
                category: "kairos_flag",
                content: ["description": action.description],
                metadata: ["importance": 4]
            ))
        }
    }

    /// Flush staged writes to persistent memory — only called on success.
    private func flushPendingWrites() async throws {
        for write in pendingWrites {
            try await memory.observe(category: write.category,
                                     content: write.content,
                                     metadata: write.metadata)
        }
        pendingWrites.removeAll()
    }

    private func recordOutcome(_ action: KairosAction, _ outcome: KairosAction.ActionOutcome) {
        // Lightweight in-memory only — no disk write for outcome records
        // (they'd create noise; the observation log is the audit trail)
        #if DEBUG
        let status: String
        switch outcome {
        case .success:              status = "✓"
        case .failure(let e):       status = "✗ \(e)"
        case .skipped(let r):       status = "– \(r)"
        }
        print("[Kairos] \(action.type.rawValue) \(status)")
        #endif
    }

    // MARK: - Observation log management

    private func trimObservationLog() {
        if observationLog.count > maxObservationLogSize {
            observationLog.removeFirst(observationLog.count - maxObservationLogSize)
        }
    }

    // MARK: - Public accessors

    func recentObservations(limit: Int = 20) -> [KairosObservation] {
        Array(observationLog.suffix(limit).reversed())
    }
}
