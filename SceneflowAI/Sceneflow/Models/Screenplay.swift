import Foundation

/// The kind of a single screenplay element. The set mirrors the industry
/// standard (and Final Draft / Arc Studio): every line on a screenplay page is
/// exactly one of these, and the type drives both on-screen formatting and
/// export.
enum ElementType: String, Codable, CaseIterable, Identifiable {
    case sceneHeading      // INT. COFFEE SHOP - DAY
    case action            // Description / stage direction
    case character         // JANE
    case parenthetical     // (whispering)
    case dialogue          // The spoken line
    case transition        // CUT TO:
    case shot              // ANGLE ON, CLOSE UP
    case section           // Outline-only section header (#)
    case synopsis          // Outline-only note (=)
    case centered          // > centered text <
    case lyric             // ~ lyrics
    case pageBreak         // forced page break

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sceneHeading: return "Scene Heading"
        case .action: return "Action"
        case .character: return "Character"
        case .parenthetical: return "Parenthetical"
        case .dialogue: return "Dialogue"
        case .transition: return "Transition"
        case .shot: return "Shot"
        case .section: return "Section"
        case .synopsis: return "Synopsis"
        case .centered: return "Centered"
        case .lyric: return "Lyric"
        case .pageBreak: return "Page Break"
        }
    }

    /// The element type a fresh line should become after the user presses
    /// return on an element of this type. This is the "smart return" behavior
    /// pro writers expect: a character cue is followed by dialogue, a scene
    /// heading by action, and so on.
    var successorOnReturn: ElementType {
        switch self {
        case .sceneHeading: return .action
        case .action: return .action
        case .character: return .dialogue
        case .parenthetical: return .dialogue
        case .dialogue: return .action
        case .transition: return .sceneHeading
        case .shot: return .action
        case .section: return .action
        case .synopsis: return .action
        case .centered: return .action
        case .lyric: return .lyric
        case .pageBreak: return .sceneHeading
        }
    }

    /// Cycle order used by the Tab key in the editor toolbar — the handful of
    /// types a writer flips between most often.
    var nextCyclingType: ElementType {
        switch self {
        case .action: return .character
        case .character: return .dialogue
        case .dialogue: return .parenthetical
        case .parenthetical: return .sceneHeading
        case .sceneHeading: return .transition
        case .transition: return .action
        default: return .action
        }
    }

    var isUppercased: Bool {
        switch self {
        case .sceneHeading, .character, .transition, .shot, .section: return true
        default: return false
        }
    }
}

/// A single line/block of the screenplay. Identifiable so SwiftUI lists can
/// diff efficiently while the writer edits.
struct ScreenplayElement: Identifiable, Codable, Hashable {
    let id: UUID
    var type: ElementType
    var text: String
    /// Production revision mark (e.g. "Blue"). `nil` means original draft.
    var revisionColor: String?
    /// Dual-dialogue pairing: when true this character/dialogue block prints
    /// side-by-side with the preceding one.
    var isDualDialogue: Bool

    init(id: UUID = UUID(),
         type: ElementType,
         text: String = "",
         revisionColor: String? = nil,
         isDualDialogue: Bool = false) {
        self.id = id
        self.type = type
        self.text = text
        self.revisionColor = revisionColor
        self.isDualDialogue = isDualDialogue
    }

    /// Text normalized for display/export (e.g. scene headings are uppercased).
    var formattedText: String {
        type.isUppercased ? text.uppercased() : text
    }
}

/// Optional cover page metadata, printed before page one on export.
struct TitlePage: Codable, Hashable {
    var title: String
    var credit: String        // "Written by"
    var author: String
    var source: String        // "Based on..."
    var contact: String
    var draftDate: String

    static let empty = TitlePage(title: "", credit: "Written by", author: "",
                                 source: "", contact: "", draftDate: "")
}

/// A complete screenplay document. This is the unit the library lists and the
/// editor, beat board, outline, stats and AI tools all operate on.
struct Screenplay: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var titlePage: TitlePage
    var elements: [ScreenplayElement]
    var beats: [Beat]
    var characters: [CharacterProfile]
    var revisions: [Revision]
    var logline: String
    var genre: String
    var createdAt: Date
    var modifiedAt: Date

    init(id: UUID = UUID(),
         title: String,
         titlePage: TitlePage = .empty,
         elements: [ScreenplayElement] = [],
         beats: [Beat] = [],
         characters: [CharacterProfile] = [],
         revisions: [Revision] = [],
         logline: String = "",
         genre: String = "",
         createdAt: Date = .now,
         modifiedAt: Date = .now) {
        self.id = id
        self.title = title
        self.titlePage = titlePage
        self.elements = elements
        self.beats = beats
        self.characters = characters
        self.revisions = revisions
        self.logline = logline
        self.genre = genre
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// All distinct character cue names, in first-appearance order. Powers the
    /// smart-type autocomplete and the character analytics.
    var characterNames: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for element in elements where element.type == .character {
            let name = element.text
                .uppercased()
                .replacingOccurrences(of: "(CONT'D)", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            ordered.append(name)
        }
        return ordered
    }

    var sceneCount: Int {
        elements.filter { $0.type == .sceneHeading }.count
    }
}
