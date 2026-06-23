import SwiftUI

/// One in-the-moment note from the live coach. The five lenses map exactly to
/// what a writer is trying to build — structure, character, pace, dialogue,
/// tone — and are graded against `CraftKnowledge` (the canon-derived rubric).
struct LiveSuggestion: Identifiable, Hashable {
    enum Lens: String, CaseIterable {
        case structure, character, pace, dialogue, tone

        var title: String { rawValue.capitalized }

        var symbol: String {
            switch self {
            case .structure: return "square.stack.3d.up"
            case .character: return "person.fill"
            case .pace: return "speedometer"
            case .dialogue: return "text.bubble.fill"
            case .tone: return "paintpalette.fill"
            }
        }

        var color: Color {
            switch self {
            case .structure: return Palette.ink
            case .character: return Palette.accent
            case .pace: return Palette.warning
            case .dialogue: return Palette.success
            case .tone: return Palette.accentDeep
            }
        }
    }

    let id = UUID()
    let lens: Lens
    let text: String

    /// Parses the live coach's `LENS: note` lines into suggestions, tolerating
    /// list bullets and stray casing, and capping at four so the banner stays
    /// glanceable rather than turning into a wall of notes.
    static func parse(_ raw: String) -> [LiveSuggestion] {
        var out: [LiveSuggestion] = []
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let label = String(line[..<colon])
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "-•*0123456789. "))
            guard let lens = Lens(rawValue: label) else { continue }
            let text = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            out.append(LiveSuggestion(lens: lens, text: text))
            if out.count == 4 { break }
        }
        return out
    }
}
