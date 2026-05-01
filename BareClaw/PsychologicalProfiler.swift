import Foundation

// MARK: - PsychologicalProfiler
//
// Builds a lightweight psychological profile from observed conversation patterns.
// Detects attachment style and communication style to let the companion tune
// its tone — more reassurance for anxious styles, more space for avoidant ones.

@MainActor
final class PsychologicalProfiler {
    static let shared = PsychologicalProfiler()

    // MARK: - Types

    enum AttachmentStyle: String, Codable {
        case unknown
        case secure     // open, comfortable with intimacy
        case anxious    // seeks reassurance, fears abandonment
        case avoidant   // keeps distance, deflects emotion
    }

    struct CommunicationStyle: Codable {
        var avgWordCount:          Double = 0
        var questionFrequency:     Double = 0   // 0–1
        var emotionalLanguageScore: Double = 0  // 0–1
        var messagesObserved:      Int    = 0
    }

    // MARK: - State

    private(set) var attachmentStyle: AttachmentStyle    = .unknown
    private(set) var commsStyle:      CommunicationStyle = CommunicationStyle()

    private let defaults       = UserDefaults.standard
    private let attachmentKey  = "psych.attachmentStyle"
    private let commsKey       = "psych.commsStyle"

    private static let anxiousSignals: [String] = [
        "are you there", "do you still", "did i say something", "are you mad",
        "you okay", "don't go", "please respond", "i miss you", "you still here"
    ]
    private static let avoidantSignals: [String] = [
        "doesn't matter", "never mind", "forget it", "i'm fine",
        "not a big deal", "whatever", "it's nothing", "doesn't matter"
    ]
    private static let emotionalWords: [String] = [
        "feel", "love", "miss", "sad", "happy", "scared",
        "hope", "wish", "heart", "hurt", "lonely", "proud"
    ]

    private init() { load() }

    // MARK: - Observation

    func observe(message: String) {
        let lower = message.lowercased()
        let words = message.split(separator: " ").count
        let n     = Double(commsStyle.messagesObserved)

        commsStyle.avgWordCount = (commsStyle.avgWordCount * n + Double(words)) / (n + 1)
        commsStyle.questionFrequency = (commsStyle.questionFrequency * n + (message.contains("?") ? 1 : 0)) / (n + 1)

        let emotionHits = Self.emotionalWords.filter { lower.contains($0) }.count
        let emotionScore = min(1.0, Double(emotionHits) / 2.0)
        commsStyle.emotionalLanguageScore = (commsStyle.emotionalLanguageScore * n + emotionScore) / (n + 1)

        commsStyle.messagesObserved += 1

        if commsStyle.messagesObserved >= 10 {
            updateAttachmentStyle(lower: lower)
        }

        save()
    }

    // MARK: - System prompt fragment

    /// Short natural-language hint injected into the companion's system prompt.
    var systemPromptFragment: String {
        guard commsStyle.messagesObserved >= 5 else { return "" }
        var parts: [String] = []

        switch attachmentStyle {
        case .anxious:
            parts.append("This person has an anxious attachment style — offer gentle reassurance naturally, never make them feel ignored.")
        case .avoidant:
            parts.append("This person tends to deflect emotion — don't push for vulnerability, let them open up at their own pace.")
        case .secure:
            parts.append("This person is emotionally open and communicative — match their warmth.")
        case .unknown:
            break
        }

        if commsStyle.avgWordCount < 8 {
            parts.append("They write short messages — keep your replies concise.")
        } else if commsStyle.avgWordCount > 40 {
            parts.append("They write long, detailed messages — you can match that depth.")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Private

    private func updateAttachmentStyle(lower: String) {
        let isAnxious  = Self.anxiousSignals.contains  { lower.contains($0) }
        let isAvoidant = Self.avoidantSignals.contains { lower.contains($0) }

        if isAnxious && !isAvoidant {
            attachmentStyle = .anxious
        } else if isAvoidant && !isAnxious {
            attachmentStyle = .avoidant
        } else if commsStyle.emotionalLanguageScore > 0.3 && commsStyle.avgWordCount > 20 {
            attachmentStyle = .secure
        }
    }

    private func save() {
        defaults.set(attachmentStyle.rawValue, forKey: attachmentKey)
        if let data = try? JSONEncoder().encode(commsStyle) {
            defaults.set(data, forKey: commsKey)
        }
    }

    private func load() {
        if let raw   = defaults.string(forKey: attachmentKey),
           let style = AttachmentStyle(rawValue: raw) {
            attachmentStyle = style
        }
        if let data  = defaults.data(forKey: commsKey),
           let style = try? JSONDecoder().decode(CommunicationStyle.self, from: data) {
            commsStyle = style
        }
    }
}
