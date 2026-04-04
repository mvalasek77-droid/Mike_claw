import Foundation

// MARK: - HermesSessionState
//
// Crash-safe session state: every meaningful change is persisted atomically
// before the operation completes, so a crash or force-quit never loses data.
//
// Three layers:
//   ConversationState  — message history, last cursor, unread count
//   WorkflowState      — long-running task state separate from chat history
//                        (can be retried safely; survives crashes)
//   TokenBudget        — hard limits with pre-turn checks; halts execution
//                        before spending over-budget

// MARK: - ConversationState

struct ConversationState: Codable {
    var id: String
    var messageCount: Int
    var lastMessageTimestamp: Date?
    var lastAssistantCursor: String?     // opaque resume token (e.g. API message ID)
    var permissionTier: PermissionTier

    static func fresh(id: String = UUID().uuidString) -> ConversationState {
        ConversationState(
            id: id, messageCount: 0,
            lastMessageTimestamp: nil,
            lastAssistantCursor: nil,
            permissionTier: .standard
        )
    }
}

// MARK: - WorkflowState

/// Long-running task state kept separate from chat history.
/// Designed for safe retry: re-running a workflow from its saved state
/// must be idempotent.
struct WorkflowState: Codable {
    enum Status: String, Codable {
        case idle, running, paused, completed, failed
    }

    var workflowId: String
    var status: Status
    var currentStepIndex: Int
    var totalSteps: Int
    var stepCheckpoints: [String: AnyCodable]   // step name → last known result
    var failureReason: String?
    var startedAt: Date?
    var updatedAt: Date

    static func idle() -> WorkflowState {
        WorkflowState(
            workflowId: UUID().uuidString,
            status: .idle,
            currentStepIndex: 0,
            totalSteps: 0,
            stepCheckpoints: [:],
            failureReason: nil,
            startedAt: nil,
            updatedAt: Date()
        )
    }

    /// Advance to next step, persisting the result of the current one.
    mutating func advanceStep(name: String, result: Any) {
        stepCheckpoints[name] = AnyCodable(result)
        currentStepIndex += 1
        updatedAt = Date()
    }
}

// MARK: - TokenBudget

struct TokenBudget: Codable {
    var sessionLimit: Int       // hard cap for this session
    var turnLimit: Int          // max tokens per single turn
    var used: Int               // running total this session
    var lastTurnUsed: Int       // tokens used in the most recent turn

    var remaining: Int { max(0, sessionLimit - used) }
    var remainingThisTurn: Int { max(0, turnLimit - lastTurnUsed) }
    var isExhausted: Bool { used >= sessionLimit }
    var usagePercent: Double { Double(used) / Double(sessionLimit) }

    /// Pre-turn check. Returns false if there is not enough budget to start a turn.
    func canStartTurn(estimatedCost: Int = 500) -> Bool {
        !isExhausted && remaining >= estimatedCost
    }

    mutating func recordTurn(prompt: Int, completion: Int) {
        let total = prompt + completion
        used += total
        lastTurnUsed = total
    }

    mutating func resetTurnCounter() {
        lastTurnUsed = 0
    }

    static func `default`() -> TokenBudget {
        TokenBudget(sessionLimit: 100_000, turnLimit: 8_000, used: 0, lastTurnUsed: 0)
    }

    static func frugal() -> TokenBudget {
        TokenBudget(sessionLimit: 20_000, turnLimit: 2_000, used: 0, lastTurnUsed: 0)
    }
}

// MARK: - Full session snapshot

struct SessionSnapshot: Codable {
    var conversation: ConversationState
    var workflow: WorkflowState
    var tokenBudget: TokenBudget
    var savedAt: Date
    var appVersion: String
    var schemaVersion: Int = 1
}

// MARK: - HermesSessionState actor

actor HermesSessionState {
    static let shared = HermesSessionState()

    private var snapshot: SessionSnapshot
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let saveFile: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hermes/session_state.json")
    }()

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Start with defaults; loadFromDisk() will replace if a saved snapshot exists
        snapshot = SessionSnapshot(
            conversation: .fresh(),
            workflow: .idle(),
            tokenBudget: .default(),
            savedAt: Date(),
            appVersion: Bundle.main.shortVersion
        )
    }

    // MARK: - Lifecycle

    /// Restore previous session from disk (call at app launch).
    func loadFromDisk() async {
        guard let data = try? Data(contentsOf: saveFile),
              let saved = try? decoder.decode(SessionSnapshot.self, from: data) else { return }
        snapshot = saved
    }

    /// Persist current snapshot atomically (crash-safe).
    func saveToDisk() async throws {
        snapshot.savedAt = Date()
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: saveFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: saveFile, options: .atomic)
    }

    // MARK: - Conversation

    func startConversation(id: String) async throws {
        snapshot.conversation = .fresh(id: id)
        snapshot.workflow = .idle()
        snapshot.tokenBudget.resetTurnCounter()
        try await saveToDisk()
    }

    func recordMessage() async throws {
        snapshot.conversation.messageCount += 1
        snapshot.conversation.lastMessageTimestamp = Date()
        try await saveToDisk()
    }

    func updateCursor(_ cursor: String) async throws {
        snapshot.conversation.lastAssistantCursor = cursor
        try await saveToDisk()
    }

    // MARK: - Workflow

    func beginWorkflow(steps: Int) async throws {
        snapshot.workflow = WorkflowState(
            workflowId: UUID().uuidString,
            status: .running,
            currentStepIndex: 0,
            totalSteps: steps,
            stepCheckpoints: [:],
            failureReason: nil,
            startedAt: Date(),
            updatedAt: Date()
        )
        try await saveToDisk()
    }

    func advanceWorkflowStep(name: String, result: Any) async throws {
        snapshot.workflow.advanceStep(name: name, result: result)
        snapshot.workflow.status = snapshot.workflow.currentStepIndex >= snapshot.workflow.totalSteps
            ? .completed : .running
        try await saveToDisk()
    }

    func failWorkflow(reason: String) async throws {
        snapshot.workflow.status = .failed
        snapshot.workflow.failureReason = reason
        snapshot.workflow.updatedAt = Date()
        try await saveToDisk()
    }

    // MARK: - Token budgeting

    /// Pre-turn budget check. Throws if budget is insufficient.
    func checkBudget(estimatedCost: Int = 500) throws {
        guard snapshot.tokenBudget.canStartTurn(estimatedCost: estimatedCost) else {
            throw SessionError.tokenBudgetExhausted(
                used: snapshot.tokenBudget.used,
                limit: snapshot.tokenBudget.sessionLimit
            )
        }
    }

    func recordTokenUsage(prompt: Int, completion: Int) async throws {
        snapshot.tokenBudget.recordTurn(prompt: prompt, completion: completion)
        try await saveToDisk()
    }

    func setBudget(_ budget: TokenBudget) async throws {
        snapshot.tokenBudget = budget
        try await saveToDisk()
    }

    // MARK: - Accessors

    var conversation: ConversationState { snapshot.conversation }
    var workflow: WorkflowState { snapshot.workflow }
    var tokenBudget: TokenBudget { snapshot.tokenBudget }
    var currentSnapshot: SessionSnapshot { snapshot }
}

// MARK: - Errors

enum SessionError: Error, LocalizedError {
    case tokenBudgetExhausted(used: Int, limit: Int)
    case workflowNotRunning
    case snapshotCorrupted

    var errorDescription: String? {
        switch self {
        case .tokenBudgetExhausted(let used, let limit):
            return "Token budget exhausted: \(used)/\(limit) used. Start a new session to continue."
        case .workflowNotRunning:
            return "No active workflow to advance."
        case .snapshotCorrupted:
            return "Session snapshot could not be decoded. Starting fresh."
        }
    }
}

// MARK: - Bundle helper

private extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }
}
