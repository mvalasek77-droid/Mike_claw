import Foundation

/// Parser and serializer for [Fountain](https://fountain.io) — the plain-text
/// markup that is the lingua franca for moving screenplays between apps.
/// Supporting it means Sceneflow can import from and export to Final Draft,
/// Highland, WriterDuet, Arc Studio and anything else that speaks Fountain.
enum FountainParser {

    // MARK: - Parse

    static func parse(_ raw: String) -> [ScreenplayElement] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var elements: [ScreenplayElement] = []
        var index = 0
        var previousWasBlank = true

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                previousWasBlank = true
                index += 1
                continue
            }

            // Forced page break: a line of 3+ equals signs.
            if trimmed.allSatisfy({ $0 == "=" }) && trimmed.count >= 3 {
                elements.append(ScreenplayElement(type: .pageBreak))
                previousWasBlank = true
                index += 1
                continue
            }

            // Forced / detected element types by leading sigil.
            if let forced = forcedElement(from: trimmed) {
                elements.append(forced)
                previousWasBlank = false
                index += 1
                continue
            }

            if isSceneHeading(trimmed) {
                elements.append(ScreenplayElement(type: .sceneHeading, text: trimmed))
                previousWasBlank = false
                index += 1
                continue
            }

            if isTransition(trimmed) {
                elements.append(ScreenplayElement(type: .transition, text: trimmed))
                previousWasBlank = false
                index += 1
                continue
            }

            // Character cue: uppercase, preceded by a blank line, and the next
            // non-empty line continues the block (dialogue / parenthetical).
            if previousWasBlank, isCharacterCue(trimmed),
               nextLineStartsDialogue(lines, after: index) {
                elements.append(ScreenplayElement(type: .character, text: trimmed))
                index += 1
                // Consume the dialogue block.
                while index < lines.count {
                    let dialogueLine = lines[index].trimmingCharacters(in: .whitespaces)
                    if dialogueLine.isEmpty { break }
                    if dialogueLine.hasPrefix("(") && dialogueLine.hasSuffix(")") {
                        elements.append(ScreenplayElement(type: .parenthetical, text: dialogueLine))
                    } else {
                        elements.append(ScreenplayElement(type: .dialogue, text: dialogueLine))
                    }
                    index += 1
                }
                previousWasBlank = true
                continue
            }

            // Default: action.
            elements.append(ScreenplayElement(type: .action, text: trimmed))
            previousWasBlank = false
            index += 1
        }

        return elements
    }

    private static func forcedElement(from line: String) -> ScreenplayElement? {
        guard let first = line.first else { return nil }
        let rest = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        switch first {
        case ".":
            // ".." is not a scene heading (it's an escaped action line).
            guard !line.hasPrefix("..") else { return nil }
            return ScreenplayElement(type: .sceneHeading, text: rest)
        case "@":
            return ScreenplayElement(type: .character, text: rest)
        case "!":
            return ScreenplayElement(type: .action, text: rest)
        case "~":
            return ScreenplayElement(type: .lyric, text: rest)
        case "#":
            return ScreenplayElement(type: .section, text: rest)
        case "=":
            return ScreenplayElement(type: .synopsis, text: rest)
        case ">":
            if line.hasSuffix("<") {
                let centered = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                return ScreenplayElement(type: .centered, text: centered)
            }
            return ScreenplayElement(type: .transition, text: rest)
        default:
            return nil
        }
    }

    private static func isSceneHeading(_ line: String) -> Bool {
        let upper = line.uppercased()
        let prefixes = ["INT.", "EXT.", "INT ", "EXT ", "EST.", "INT./EXT.",
                        "I/E.", "I/E ", "INT/EXT"]
        return prefixes.contains { upper.hasPrefix($0) }
    }

    private static func isTransition(_ line: String) -> Bool {
        let upper = line.uppercased()
        guard upper == line else { return false } // must be all caps
        return upper.hasSuffix("TO:") || upper == "CUT TO BLACK." || upper == "FADE OUT." || upper == "FADE IN:"
    }

    private static func isCharacterCue(_ line: String) -> Bool {
        let core = line.replacingOccurrences(of: "(CONT'D)", with: "")
            .replacingOccurrences(of: "(V.O.)", with: "")
            .replacingOccurrences(of: "(O.S.)", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty, core.count <= 50 else { return false }
        // Must contain a letter and be uppercase (ignoring digits/punctuation).
        let letters = core.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        return letters == letters.uppercased()
    }

    private static func nextLineStartsDialogue(_ lines: [String], after index: Int) -> Bool {
        let next = index + 1
        guard next < lines.count else { return false }
        return !lines[next].trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Serialize

    static func serialize(_ elements: [ScreenplayElement]) -> String {
        var out = ""
        var previousType: ElementType?

        for element in elements {
            let needsBlankBefore: Bool
            switch element.type {
            case .sceneHeading, .action, .character, .transition, .shot, .section, .synopsis, .centered:
                needsBlankBefore = previousType != nil
            case .dialogue, .parenthetical, .lyric, .pageBreak:
                needsBlankBefore = previousType == .pageBreak
            }

            if needsBlankBefore && !out.isEmpty { out += "\n" }

            switch element.type {
            case .pageBreak:
                out += "===\n"
            case .centered:
                out += ">\(element.text)<\n"
            case .section:
                out += "# \(element.text)\n"
            case .synopsis:
                out += "= \(element.text)\n"
            case .lyric:
                out += "~ \(element.text)\n"
            default:
                out += element.formattedText + "\n"
            }
            previousType = element.type
        }
        return out
    }
}
