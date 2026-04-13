import Foundation

// MARK: - Role

enum MessageRole {
    case user
    case assistant
}

// MARK: - TrackedMessage

private struct TrackedMessage {
    let role: MessageRole
    let text: String
    let timestamp: Date
}

// MARK: - HermesContextTracker
//
// Maintains a sliding window of recent messages and extracts the current
// topic + intent without any network calls.
//
// Used by HermesIntegration.currentTopic() and HermesProactiveEngine
// for richer, more accurate suggestions.

actor HermesContextTracker {
    static let shared = HermesContextTracker()

    /// How many messages to keep in the active window.
    private let windowSize = 20

    private var window: [TrackedMessage] = []

    // Cache so we don't re-derive on every call
    private var cachedTopic: String?
    private var topicDirty = true

    private init() {}

    // MARK: - Ingestion

    /// Add a new message to the sliding window.
    func ingest(text: String, role: MessageRole) {
        let msg = TrackedMessage(role: role, text: text, timestamp: Date())
        window.append(msg)
        if window.count > windowSize { window.removeFirst() }
        topicDirty = true
    }

    // MARK: - Derived context

    /// Best-guess "current topic" from the recent window.
    /// Returns nil if the window is empty.
    func currentTopic() -> String? {
        guard !window.isEmpty else { return nil }
        if !topicDirty, let cached = cachedTopic { return cached }
        let topic = deriveTopic()
        cachedTopic = topic
        topicDirty = false
        return topic
    }

    /// Rough intent category of the most recent user message.
    func currentIntent() -> Intent? {
        guard let lastUser = window.last(where: { $0.role == .user }) else { return nil }
        return classifyIntent(lastUser.text)
    }

    /// Plain summary of the window — useful for injecting context into a new conversation.
    func sessionSummary() -> String {
        let userLines = window
            .filter { $0.role == .user }
            .suffix(5)
            .map { "• \($0.text.prefix(120))" }
            .joined(separator: "\n")
        guard !userLines.isEmpty else { return "No activity yet." }
        return "Recent messages:\n\(userLines)"
    }

    // MARK: - Topic derivation

    private static let stopwords: Set<String> = [
        "the","and","for","are","but","not","you","all","can","had","her","was","one",
        "our","out","day","get","has","him","his","how","man","new","now","old","see",
        "two","way","who","did","its","let","put","say","she","too","use","that","with",
        "have","this","will","your","from","they","know","want","been","good","much",
        "some","time","very","when","come","here","just","like","long","make","many",
        "more","only","over","such","take","than","them","well","were","what","also",
        "into","most","then","there","these","think","those","about","after","being",
        "could","going","their","where","which","would","should","because"
    ]

    private func deriveTopic() -> String? {
        // Weight user messages 2× over assistant messages
        let corpus = window.map { msg -> String in
            let weight = msg.role == .user ? 2 : 1
            return Array(repeating: msg.text, count: weight).joined(separator: " ")
        }.joined(separator: " ")

        let words = corpus
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 3 && !Self.stopwords.contains($0) }

        let freq = Dictionary(words.map { ($0, 1) }, uniquingKeysWith: +)
        let top = freq.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        return top.isEmpty ? nil : top.joined(separator: ", ")
    }

    // MARK: - Intent classification

    enum Intent: String {
        case question       // asking for information
        case debugRequest   // fixing a bug or error
        case buildRequest   // creating something new
        case explainRequest // asking for an explanation
        case editRequest    // modifying existing content
        case other
    }

    private func classifyIntent(_ text: String) -> Intent {
        let t = text.lowercased()

        let debugSignals  = ["error","bug","fix","crash","fail","broken","not working","exception","issue"]
        let buildSignals  = ["create","build","make","add","implement","generate","write","new"]
        let explainSignals = ["explain","what is","what are","how does","why does","tell me","describe"]
        let editSignals   = ["change","update","modify","rename","refactor","move","delete","remove"]
        let questionSignals = ["?","how","what","when","where","who","which","why","can you"]

        func matches(_ signals: [String]) -> Bool { signals.contains { t.contains($0) } }

        if matches(debugSignals)   { return .debugRequest }
        if matches(buildSignals)   { return .buildRequest }
        if matches(explainSignals) { return .explainRequest }
        if matches(editSignals)    { return .editRequest }
        if matches(questionSignals){ return .question }
        return .other
    }
}
