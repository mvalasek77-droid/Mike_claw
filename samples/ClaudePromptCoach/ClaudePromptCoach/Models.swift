import Foundation

// MARK: - Coaching modes

/// The four coaching modes shown as pill buttons on the session screen.
enum CoachMode: String, Codable, CaseIterable, Identifiable {
    case interview
    case specFirst
    case subAgents
    case verify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interview: return "Interview me"
        case .specFirst: return "Spec first"
        case .subAgents: return "Launch sub-agents"
        case .verify: return "Verify before you build"
        }
    }

    var icon: String {
        switch self {
        case .interview: return "bubble.left.and.bubble.right"
        case .specFirst: return "doc.text"
        case .subAgents: return "square.split.2x2"
        case .verify: return "checkmark.shield"
        }
    }

    var summary: String {
        switch self {
        case .interview:
            return "The coach flips the script and asks you 3-5 questions before drafting anything."
        case .specFirst:
            return "Resolve ambiguity on paper: a short implementation spec is drafted before the prompt."
        case .subAgents:
            return "Complex asks are split into parallel sub-agent prompts plus a synth prompt."
        case .verify:
            return "A verification checklist is appended so the model checks itself before touching real files or APIs."
        }
    }
}

// MARK: - Interview

/// One targeted question the coach asks during a session.
struct CoachQuestion: Identifiable, Hashable {
    let id: UUID
    let prompt: String
    let detail: String
    let placeholder: String

    init(prompt: String, detail: String, placeholder: String) {
        self.id = UUID()
        self.prompt = prompt
        self.detail = detail
        self.placeholder = placeholder
    }
}

/// The Skill the coach assembles from a finished interview, before it is saved.
struct SkillDraft {
    var goal: String
    var mode: CoachMode
    var title: String
    var summary: String
    var instructions: [String]
    var tools: [String]
    var specDocument: String?
    var subPrompts: [String]
    var synthPrompt: String?
    var verificationChecklist: [String]
    /// Rules surfaced by the session, offered by the capture dialog afterwards.
    var learnedRules: [String]
}

// MARK: - Library

/// A visible, never-silent record of every change made to a Skill.
struct ChangelogEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var summary: String

    init(summary: String, date: Date = .now) {
        self.id = UUID()
        self.date = date
        self.summary = summary
    }
}

/// A reusable Skill: title, one-line description, step-by-step instructions, optional tools.
struct Skill: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var summary: String
    var instructions: [String]
    var tools: [String]
    var timesUsed: Int
    var createdAt: Date
    /// Timestamps of every update; drives the heat trail on the card.
    var updateDates: [Date]
    var changelog: [ChangelogEntry]
    var lastEvolvedAt: Date?
    var isStarter: Bool
    /// Titles of Skills this one was chained from, if composed.
    var chainedFrom: [String]

    init(
        title: String,
        summary: String,
        instructions: [String],
        tools: [String] = [],
        isStarter: Bool = false,
        chainedFrom: [String] = []
    ) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.instructions = instructions
        self.tools = tools
        self.timesUsed = 0
        self.createdAt = .now
        self.updateDates = [.now]
        self.changelog = [ChangelogEntry(summary: isStarter ? "Shipped with the starter library" : "Created from a coach session")]
        self.lastEvolvedAt = nil
        self.isStarter = isStarter
        self.chainedFrom = chainedFrom
    }

    /// True while the heartbeat "evolved" indicator should show on the card.
    var recentlyEvolved: Bool {
        guard let evolved = lastEvolvedAt else { return false }
        return Date.now.timeIntervalSince(evolved) < 3 * 24 * 3600
    }
}

/// Where a draft lands when it fails the Taste Test: a one-off note, not a Skill.
struct OneOffNote: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date

    init(title: String, body: String) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.createdAt = .now
    }
}
