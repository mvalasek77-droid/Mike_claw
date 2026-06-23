import Foundation

/// Estimates page count and runtime, and derives the analytics the Stats tab
/// shows. The model is the long-established US-letter screenplay geometry:
/// ~55 typed lines per page in 12pt Courier, with column widths that differ by
/// element type. It's an estimate (true pagination requires a layout pass),
/// but it tracks Final Draft's page count closely for normal scripts and is
/// stable enough to drive runtime and progress UI.
enum PaginationEngine {
    static let linesPerPage = 55.0

    /// Character width (in columns) available to each element type.
    private static func wrapWidth(for type: ElementType) -> Int {
        switch type {
        case .dialogue: return 35
        case .parenthetical: return 25
        case .character: return 38
        case .sceneHeading, .action, .shot: return 61
        case .transition: return 61
        default: return 61
        }
    }

    /// Blank lines that precede an element on the page.
    private static func leadingBlankLines(for type: ElementType) -> Double {
        switch type {
        case .sceneHeading: return 2
        case .action, .character, .transition, .shot: return 1
        default: return 0
        }
    }

    private static func lineCount(for element: ScreenplayElement) -> Double {
        if element.type == .pageBreak { return linesPerPage }
        let width = wrapWidth(for: element.type)
        let text = element.formattedText
        guard !text.isEmpty else { return 1 + leadingBlankLines(for: element.type) }

        // Sum wrapped lines across hard line breaks.
        let wrapped = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0.0) { acc, line in
            acc + max(1.0, ceil(Double(line.count) / Double(width)))
        }
        return wrapped + leadingBlankLines(for: element.type)
    }

    static func totalLines(_ elements: [ScreenplayElement]) -> Double {
        elements.reduce(0) { $0 + lineCount(for: $1) }
    }

    static func pageCount(_ elements: [ScreenplayElement]) -> Double {
        max(0, totalLines(elements) / linesPerPage)
    }

    /// Industry rule of thumb: one page ≈ one minute of screen time.
    static func runtimeMinutes(_ elements: [ScreenplayElement]) -> Double {
        pageCount(elements)
    }

    static func runtimeDescription(_ elements: [ScreenplayElement]) -> String {
        let minutes = Int(runtimeMinutes(elements).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// One character's share of the dialogue. A named type (rather than a tuple)
/// so it's Identifiable for Swift Charts.
struct DialogueShare: Identifiable, Hashable {
    let name: String
    let words: Int
    var id: String { name }
}

/// A fully derived analytics snapshot for one screenplay.
struct ScriptAnalytics {
    let pageCount: Double
    let runtime: String
    let sceneCount: Int
    let wordCount: Int
    let dialogueWordCount: Int
    let actionWordCount: Int
    /// Dialogue words spoken per character, sorted descending.
    let dialogueByCharacter: [DialogueShare]
    /// INT vs EXT scene split.
    let interiorScenes: Int
    let exteriorScenes: Int

    init(_ screenplay: Screenplay) {
        let elements = screenplay.elements
        pageCount = PaginationEngine.pageCount(elements)
        runtime = PaginationEngine.runtimeDescription(elements)
        sceneCount = screenplay.sceneCount

        func words(_ s: String) -> Int {
            s.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        }

        var dialogueWords = 0
        var actionWords = 0
        var perCharacter: [String: Int] = [:]
        var currentSpeaker: String?
        var interior = 0
        var exterior = 0

        for element in elements {
            switch element.type {
            case .action, .shot:
                actionWords += words(element.text)
            case .character:
                currentSpeaker = element.text
                    .uppercased()
                    .replacingOccurrences(of: "(CONT'D)", with: "")
                    .trimmingCharacters(in: .whitespaces)
            case .dialogue:
                let w = words(element.text)
                dialogueWords += w
                if let speaker = currentSpeaker, !speaker.isEmpty {
                    perCharacter[speaker, default: 0] += w
                }
            case .sceneHeading:
                let upper = element.text.uppercased()
                if upper.hasPrefix("INT") { interior += 1 }
                else if upper.hasPrefix("EXT") { exterior += 1 }
                else if upper.contains("INT") { interior += 1 }
                else if upper.contains("EXT") { exterior += 1 }
            default:
                break
            }
        }

        dialogueWordCount = dialogueWords
        actionWordCount = actionWords
        wordCount = dialogueWords + actionWords
        dialogueByCharacter = perCharacter
            .map { DialogueShare(name: $0.key, words: $0.value) }
            .sorted { $0.words > $1.words }
        interiorScenes = interior
        exteriorScenes = exterior
    }
}
