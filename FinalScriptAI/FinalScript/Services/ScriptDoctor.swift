import Foundation

/// One finding from `ScriptDoctor`. Severity is about reader impact, not
/// formatting correctness — this is craft, not Fountain parsing.
struct ScriptIssue: Identifiable, Hashable {
    enum Severity: Int, Comparable {
        case info, suggestion, warning
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id = UUID()
    let severity: Severity
    let category: String
    let title: String
    let detail: String
    /// The element this finding is about, if any, so the UI can jump to it.
    let elementID: UUID?

    var symbol: String {
        switch severity {
        case .warning: return "exclamationmark.triangle.fill"
        case .suggestion: return "lightbulb.fill"
        case .info: return "info.circle.fill"
        }
    }
}

/// A deterministic, instant (no AI call) pass over a screenplay that flags the
/// craft and format smells a contest reader, agent, or studio screener
/// actually docks scripts for: dense unbroken text, monologue dumps, character
/// naming drift, parenthetical overdirecting, adverb crutches, and slow opens.
/// Final Draft and Arc Studio check Fountain/format compliance; neither one
/// reads the page the way the human on the other end will, so this fills that
/// gap instead of duplicating either of them.
enum ScriptDoctor {
    private static let actionWrapWidth = 61
    private static let dialogueWrapWidth = 35

    static func analyze(_ screenplay: Screenplay) -> [ScriptIssue] {
        var issues: [ScriptIssue] = []
        flagDenseActionBlocks(screenplay, into: &issues)
        flagMonologueDumps(screenplay, into: &issues)
        flagSimilarCharacterNames(screenplay, into: &issues)
        flagParentheticalOveruse(screenplay, into: &issues)
        flagAdverbCrutches(screenplay, into: &issues)
        flagUnintroducedSpeakers(screenplay, into: &issues)
        flagSlowOpen(screenplay, into: &issues)
        return issues.sorted { $0.severity > $1.severity }
    }

    // MARK: - Wall-of-text action

    /// A screener's eye skips dense gray action blocks. Five+ wrapped lines
    /// without a break is the rule of thumb working readers use.
    private static func flagDenseActionBlocks(_ screenplay: Screenplay, into issues: inout [ScriptIssue]) {
        for element in screenplay.elements where element.type == .action {
            let lines = wrappedLineCount(element.text, width: actionWrapWidth)
            guard lines > 5 else { continue }
            issues.append(ScriptIssue(
                severity: .suggestion,
                category: "Pacing",
                title: "Dense action block (\(lines) lines)",
                detail: "Long unbroken description reads as a gray wall on the page. Consider breaking it at a beat, or cutting to only what's essential to see.",
                elementID: element.id
            ))
        }
    }

    // MARK: - Monologue dumps

    /// A single dialogue block running past ~8 lines is a monologue; flag it
    /// so the writer can confirm it's earned, not just unedited.
    private static func flagMonologueDumps(_ screenplay: Screenplay, into issues: inout [ScriptIssue]) {
        var currentSpeaker: String?
        for element in screenplay.elements {
            switch element.type {
            case .character:
                currentSpeaker = element.text
            case .dialogue:
                let lines = wrappedLineCount(element.text, width: dialogueWrapWidth)
                guard lines > 8 else { continue }
                let who = currentSpeaker.map { " (\($0))" } ?? ""
                issues.append(ScriptIssue(
                    severity: .suggestion,
                    category: "Dialogue",
                    title: "Long monologue\(who) — \(lines) lines",
                    detail: "Unbroken speeches this long ask a lot of a reader skimming for momentum. Worth a gut check on whether every line earns its place.",
                    elementID: element.id
                ))
            case .action, .sceneHeading:
                currentSpeaker = nil
            default:
                break
            }
        }
    }

    // MARK: - Character naming drift

    /// Flags character names that look like variants of each other (e.g.
    /// "DETECTIVE MARA" and "MARA") — usually a continuity slip rather than
    /// two different people, and screeners read it as sloppy.
    private static func flagSimilarCharacterNames(_ screenplay: Screenplay, into issues: inout [ScriptIssue]) {
        let names = screenplay.characterNames
        guard names.count > 1 else { return }
        var flaggedPairs = Set<String>()
        for i in 0..<names.count {
            for j in (i + 1)..<names.count {
                let a = names[i], b = names[j]
                guard a.count >= 3, b.count >= 3, a != b else { continue }
                guard a.contains(b) || b.contains(a) else { continue }
                let key = [a, b].sorted().joined(separator: "|")
                guard flaggedPairs.insert(key).inserted else { continue }
                issues.append(ScriptIssue(
                    severity: .warning,
                    category: "Continuity",
                    title: "Possible name drift: \"\(a)\" / \"\(b)\"",
                    detail: "These cues look like they might be the same character credited inconsistently. If so, pick one form — readers will assume two characters otherwise.",
                    elementID: nil
                ))
            }
        }
    }

    // MARK: - Parenthetical overuse

    /// More than ~1 parenthetical for every 3 dialogue blocks for a character
    /// reads as over-directing the actor — a classic amateur tell.
    private static func flagParentheticalOveruse(_ screenplay: Screenplay, into issues: inout [ScriptIssue]) {
        var dialogueCount: [String: Int] = [:]
        var parentheticalCount: [String: Int] = [:]
        var currentSpeaker: String?

        for element in screenplay.elements {
            switch element.type {
            case .character:
                currentSpeaker = element.text.replacingOccurrences(of: "(CONT'D)", with: "")
                    .trimmingCharacters(in: .whitespaces)
            case .dialogue:
                guard let speaker = currentSpeaker else { continue }
                dialogueCount[speaker, default: 0] += 1
            case .parenthetical:
                guard let speaker = currentSpeaker else { continue }
                parentheticalCount[speaker, default: 0] += 1
            case .action, .sceneHeading:
                currentSpeaker = nil
            default:
                break
            }
        }

        for (speaker, dCount) in dialogueCount where dCount >= 4 {
            let pCount = parentheticalCount[speaker] ?? 0
            guard Double(pCount) / Double(dCount) > 0.3 else { continue }
            issues.append(ScriptIssue(
                severity: .suggestion,
                category: "Dialogue",
                title: "Heavy parenthetical use for \(speaker)",
                detail: "\(pCount) parentheticals across \(dCount) dialogue blocks. Direction belongs to the director and actor — let the dialogue itself carry the tone where it can.",
                elementID: nil
            ))
        }
    }

    // MARK: - Adverb crutches

    /// Action lines leaning on adverbs ("walks slowly, angrily") instead of a
    /// precise verb are a well-known craft smell readers flag in coverage.
    private static func flagAdverbCrutches(_ screenplay: Screenplay, into issues: inout [ScriptIssue]) {
        let commonNonCrutch: Set<String> = ["only", "really", "finally", "early", "family", "supply"]
        for element in screenplay.elements where element.type == .action {
            let words = element.text.split(separator: " ")
            let adverbs = words.filter { word in
                let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                return lower.hasSuffix("ly") && lower.count > 4 && !commonNonCrutch.contains(lower)
            }
            guard adverbs.count >= 3 else { continue }
            issues.append(ScriptIssue(
                severity: .info,
                category: "Craft",
                title: "Adverb-heavy action line",
                detail: "\(adverbs.count) adverbs in one action line (\(adverbs.prefix(3).map(String.init).joined(separator: ", "))…). Often a sign a stronger verb is available.",
                elementID: element.id
            ))
        }
    }

    // MARK: - Unintroduced speakers

    /// A character who speaks but is never named in an action line beforehand
    /// has no on-page introduction — readers specifically look for a brief
    /// physical/age tag on a character's first appearance.
    private static func flagUnintroducedSpeakers(_ screenplay: Screenplay, into issues: inout [ScriptIssue]) {
        var introduced = Set<String>()
        var warnedAlready = Set<String>()

        for element in screenplay.elements {
            switch element.type {
            case .action:
                let upper = element.text.uppercased()
                for name in screenplay.characterNames where upper.contains(name) {
                    introduced.insert(name)
                }
            case .character:
                let name = element.text.replacingOccurrences(of: "(CONT'D)", with: "")
                    .trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, !introduced.contains(name), warnedAlready.insert(name).inserted else { continue }
                issues.append(ScriptIssue(
                    severity: .suggestion,
                    category: "Craft",
                    title: "\(name) speaks before being introduced",
                    detail: "No action line mentions \(name) before their first line. A brief intro (name, age, a defining detail) on first appearance helps a reader picture the character immediately.",
                    elementID: element.id
                ))
            default:
                break
            }
        }
    }

    // MARK: - Slow open

    /// The first ~10 pages are what decides whether a reader keeps going.
    /// Flag a script whose opening leans entirely on description with no
    /// dialogue yet — a common note in coverage on slow opens.
    private static func flagSlowOpen(_ screenplay: Screenplay, into issues: inout [ScriptIssue]) {
        let openingPageLines = 55.0 * 10.0 // ~10 pages at the standard 55 lines/page
        var lineBudget = openingPageLines
        var sawDialogue = false

        for element in screenplay.elements {
            guard lineBudget > 0 else { break }
            if element.type == .dialogue { sawDialogue = true; break }
            let width = element.type == .action ? actionWrapWidth : dialogueWrapWidth
            lineBudget -= Double(wrappedLineCount(element.text, width: width)) + 1
        }

        guard !sawDialogue, !screenplay.elements.isEmpty else { return }
        issues.append(ScriptIssue(
            severity: .warning,
            category: "Pacing",
            title: "No dialogue in the first ~10 pages",
            detail: "Readers and contest screeners weigh the opening pages heavily. A long silent stretch up top is a real risk unless the visual storytelling is doing a lot of work.",
            elementID: nil
        ))
    }

    // MARK: - Shared

    private static func wrappedLineCount(_ text: String, width: Int) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { acc, line in
            acc + max(1, Int(ceil(Double(line.count) / Double(width))))
        }
    }
}
