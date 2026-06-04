import Foundation

enum DecodeTone: String, CaseIterable, Identifiable, Codable {
    case gentle
    case groupChat
    case spicy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gentle: return "Gentle"
        case .groupChat: return "Group Chat"
        case .spicy: return "Crude-ish"
        }
    }

    var promptValue: String {
        switch self {
        case .gentle: return "gentle, warm, funny, clear"
        case .groupChat: return "group-chat funny, psychology-informed, blunt without being mean"
        case .spicy: return "a little crude, playful, truthful, never sexually explicit"
        }
    }
}

enum DecodeContext: String, CaseIterable, Identifiable, Codable {
    case dating
    case friend
    case work

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dating: return "Dating"
        case .friend: return "Friend"
        case .work: return "Work"
        }
    }
}

struct DecodeResult: Codable, Equatable {
    var headline: String
    var translation: String
    var psychology: String
    var receipts: [String]
    var suggestedReplies: [String]
    var realityScore: Int
    var energy: String
    var flags: [String]

    static let placeholder = DecodeResult(
        headline: "Paste the text. The group chat is waiting.",
        translation: "No verdict yet. Drop the message and pick the tone.",
        psychology: "The app looks for ambiguity, effort, timing, repair attempts, and whether the words match a real plan.",
        receipts: ["Low effort", "Mixed signals", "Actual clarity"],
        suggestedReplies: [
            "I like clear plans. What day and time works?",
            "That sounds cute, but vague. Try again with a location.",
            "I am not mad, I am just no longer donating free confusion."
        ],
        realityScore: 50,
        energy: "Unopened envelope",
        flags: []
    )

    var normalized: DecodeResult {
        DecodeResult(
            headline: headline.trimmingCharacters(in: .whitespacesAndNewlines),
            translation: translation.trimmingCharacters(in: .whitespacesAndNewlines),
            psychology: psychology.trimmingCharacters(in: .whitespacesAndNewlines),
            receipts: receipts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            suggestedReplies: suggestedReplies.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            realityScore: min(100, max(0, realityScore)),
            energy: energy.trimmingCharacters(in: .whitespacesAndNewlines),
            flags: flags.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
    }
}

struct DecodeOutcome: Equatable {
    let result: DecodeResult
    let usedFallback: Bool
}
