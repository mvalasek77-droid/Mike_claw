import Foundation

/// Parser and serializer for [Fountain](https://fountain.io) — the plain-text
/// markup that is the lingua franca for moving screenplays between apps.
/// Supporting it means Final Script AI can import from and export to Final Draft,
/// Highland, WriterDuet, Arc Studio and anything else that speaks Fountain.
enum FountainParser {

    // MARK: - Parse

    static func parse(_ raw: String) -> [ScreenplayElement] {
        parseDocument(raw).elements
    }

    /// Like `parse`, but also extracts a leading Fountain title-page block
    /// ("Title:", "Author:", ... terminated by a blank line) when present.
    static func parseDocument(_ raw: String) -> (titlePage: TitlePage?, elements: [ScreenplayElement]) {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var elements: [ScreenplayElement] = []
        var index = 0
        var previousWasBlank = true
        var lastDialogueBlockRange: Range<Int>?

        var titlePage: TitlePage?
        if let (page, consumed) = extractTitlePage(lines) {
            titlePage = page
            index = consumed
        }

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

            if isShot(trimmed) {
                elements.append(ScreenplayElement(type: .shot, text: trimmed))
                previousWasBlank = false
                index += 1
                continue
            }

            // Character cue: uppercase, preceded by a blank line, and the next
            // non-empty line continues the block (dialogue / parenthetical).
            // A trailing "^" marks this block as dual dialogue with the block
            // immediately before it.
            if previousWasBlank, isCharacterCue(trimmed),
               nextLineStartsDialogue(lines, after: index) {
                var cueText = trimmed
                let isDual = cueText.hasSuffix("^")
                if isDual {
                    cueText = String(cueText.dropLast()).trimmingCharacters(in: .whitespaces)
                }
                let blockStart = elements.count
                elements.append(ScreenplayElement(type: .character, text: cueText, isDualDialogue: isDual))
                index += 1
                // Consume the dialogue block.
                while index < lines.count {
                    let dialogueLine = lines[index].trimmingCharacters(in: .whitespaces)
                    if dialogueLine.isEmpty { break }
                    if dialogueLine.hasPrefix("(") && dialogueLine.hasSuffix(")") {
                        elements.append(ScreenplayElement(type: .parenthetical, text: dialogueLine, isDualDialogue: isDual))
                    } else {
                        elements.append(ScreenplayElement(type: .dialogue, text: dialogueLine, isDualDialogue: isDual))
                    }
                    index += 1
                }
                let blockEnd = elements.count
                if isDual, let previousRange = lastDialogueBlockRange {
                    for i in previousRange { elements[i].isDualDialogue = true }
                }
                lastDialogueBlockRange = blockStart..<blockEnd
                previousWasBlank = true
                continue
            }

            // Default: action.
            elements.append(ScreenplayElement(type: .action, text: trimmed))
            previousWasBlank = false
            index += 1
        }

        return (titlePage, elements)
    }

    /// Recognizes a leading "Key: value" title-page block (Fountain spec),
    /// terminated by a blank line. Returns the parsed page and how many lines
    /// it consumed, or `nil` if the document doesn't open with one.
    private static func extractTitlePage(_ lines: [String]) -> (TitlePage, Int)? {
        let knownKeys: Set<String> = ["title", "credit", "author", "authors",
                                       "source", "draft date", "contact", "notes"]
        var values: [String: String] = [:]
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            guard let colonIndex = trimmed.firstIndex(of: ":") else { break }
            let key = trimmed[..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
            guard knownKeys.contains(key) else { break }
            let value = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            values[key] = value
            index += 1
        }
        guard !values.isEmpty else { return nil }
        if index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }
        let page = TitlePage(
            title: values["title"] ?? "",
            credit: values["credit"] ?? "Written by",
            author: values["author"] ?? values["authors"] ?? "",
            source: values["source"] ?? "",
            contact: values["contact"] ?? "",
            draftDate: values["draft date"] ?? ""
        )
        return (page, index)
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
        let prefixes = ["INT.", "EXT.", "INT ", "EXT ", "EST.",
                        "INT./EXT.", "EXT./INT.", "INT/EXT", "EXT/INT",
                        "I/E.", "I/E "]
        return prefixes.contains { upper.hasPrefix($0) }
    }

    private static func isTransition(_ line: String) -> Bool {
        let upper = line.uppercased()
        guard upper == line else { return false } // must be all caps
        return upper.hasSuffix("TO:") || upper == "CUT TO BLACK." || upper == "FADE OUT." || upper == "FADE IN:"
    }

    private static func isShot(_ line: String) -> Bool {
        let upper = line.uppercased()
        guard upper == line else { return false } // must be all caps
        let prefixes = ["ANGLE ON", "CLOSE ON", "CLOSE-UP", "CLOSEUP",
                        "EXTREME CLOSE-UP", "EXTREME CLOSE UP", "WIDE SHOT",
                        "POV", "INSERT", "TIGHT ON", "TRACKING SHOT", "AERIAL SHOT"]
        return prefixes.contains { upper.hasPrefix($0) }
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

    /// `serialize`, prefixed with a Fountain title-page block when the page
    /// has any non-empty fields, so round-tripping through export/import
    /// preserves title metadata.
    static func serializeDocument(titlePage: TitlePage, elements: [ScreenplayElement]) -> String {
        var lines: [String] = []
        if !titlePage.title.isEmpty { lines.append("Title: \(titlePage.title)") }
        if !titlePage.credit.isEmpty { lines.append("Credit: \(titlePage.credit)") }
        if !titlePage.author.isEmpty { lines.append("Author: \(titlePage.author)") }
        if !titlePage.source.isEmpty { lines.append("Source: \(titlePage.source)") }
        if !titlePage.contact.isEmpty { lines.append("Contact: \(titlePage.contact)") }
        if !titlePage.draftDate.isEmpty { lines.append("Draft date: \(titlePage.draftDate)") }
        guard !lines.isEmpty else { return serialize(elements) }
        return lines.joined(separator: "\n") + "\n\n" + serialize(elements)
    }
}
