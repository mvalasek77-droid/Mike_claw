import Foundation

// MARK: - ASMRTextProcessor
//
// Final text pass before AVSpeechSynthesizer — the "smoothing layer."
//
// Inspired by the cadence of intimate ASMR delivery: unhurried, breath-aware,
// close. It doesn't change what the companion says — only how it lands
// when spoken. Think of it as teaching the synthesizer to breathe.
//
// What it does:
//   1. Strips markdown, em-dashes, parentheticals, URLs — anything that
//      sounds jarring when read aloud
//   2. Softens stiff formal connectors ("However" → "Though")
//   3. Injects comma breath-pauses at natural clause joins
//   4. At .falling/.inLove: adds ellipsis pauses before intimate phrases
//   5. Female mode: softer, closer, more breath between clauses
//   6. Male mode: measured, deliberate, more silence before key thoughts

struct ASMRTextProcessor {

    // MARK: - Entry point

    static func process(_ text: String,
                        gender: CompanionGender,
                        loveStage: LoveStage) -> String {
        var t = text
        t = strip(t)
        t = softenConnectors(t)
        t = injectBreathPauses(t, gender: gender, stage: loveStage)
        t = addIntimacyPauses(t, stage: loveStage)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Strip formatting artifacts

    private static func strip(_ text: String) -> String {
        var t = text

        // Markdown tokens — read literally by synthesizer otherwise
        for token in ["**", "__", "*", "_", "`", "# ", "## ", "### "] {
            t = t.replacingOccurrences(of: token, with: "")
        }

        // Em-dash / en-dash → comma pause (more natural in speech)
        t = t.replacingOccurrences(of: " — ", with: ", ")
        t = t.replacingOccurrences(of: "—",    with: ", ")
        t = t.replacingOccurrences(of: " – ", with: ", ")
        t = t.replacingOccurrences(of: "–",    with: ", ")

        // Parentheticals get read as awkward insertions — remove short ones
        t = t.replacingOccurrences(of: #"\([^)]{1,60}\)"#, with: "",
                                   options: .regularExpression)

        // URLs are unlistenable
        t = t.replacingOccurrences(of: #"https?://\S+"#, with: "",
                                   options: .regularExpression)

        // Collapse multiple spaces / newlines
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ",
                                   options: .regularExpression)

        // Remove trailing space before punctuation
        t = t.replacingOccurrences(of: #"\s([.,!?])"#, with: "$1",
                                   options: .regularExpression)

        return t
    }

    // MARK: - Soften stiff formal connectors

    // ASMR speech never sounds like a report. These words kill warmth.
    private static func softenConnectors(_ text: String) -> String {
        var t = text
        let subs: [(String, String)] = [
            ("However, ",           "Though, "),
            ("However ",            "Though, "),
            ("Nevertheless, ",      "Even so, "),
            ("Nevertheless ",       "Even so, "),
            ("Furthermore, ",       "And, "),
            ("Furthermore ",        "And, "),
            ("In conclusion, ",     "So, "),
            ("In summary, ",        "So, "),
            ("In addition, ",       "Also, "),
            ("Additionally, ",      "Also, "),
            ("Subsequently, ",      "Then, "),
            ("Consequently, ",      "So, "),
            ("Therefore, ",         "So, "),
            ("Moreover, ",          "And, "),
            ("As a result, ",       "So, "),
            ("It should be noted ", "Worth saying, "),
            ("It is worth noting ", "Worth saying, "),
            ("Essentially, ",       "Really, "),
            ("Ultimately, ",        "In the end, "),
            ("Certainly, ",         "Of course, "),
            ("Obviously, ",         "Right, "),
            ("Absolutely, ",        "Yes, "),
        ]
        for (from, to) in subs {
            t = t.replacingOccurrences(of: from, with: to)
        }
        return t
    }

    // MARK: - Inject breath pauses at clause boundaries

    // Commas and semicolons cause AVSpeechSynthesizer to pause briefly.
    // We inject them at natural breath points that the LLM may have skipped.
    // More pauses at higher love stages — deeper intimacy = more breathing room.

    private static func injectBreathPauses(_ text: String,
                                            gender: CompanionGender,
                                            stage: LoveStage) -> String {
        guard stage >= .drawn else { return text }
        var t = text

        // Core clause joins — always breathe here
        let corePauses: [(String, String)] = [
            (" and I ",       ", and I "),
            (" and you ",     ", and you "),
            (" but I ",       ", but I "),
            (" but you ",     ", but you "),
            (" because I ",   ", because I "),
            (" because you ", ", because you "),
            (" when you ",    ", when you "),
            (" when I ",      ", when I "),
            (" so I ",        ", so I "),
            (" so you ",      ", so you "),
            (" though I ",    ", though I "),
            (" though you ",  ", though you "),
            (" if you ",      ", if you "),
            (" if I ",        ", if I "),
        ]
        for (from, to) in corePauses {
            t = t.replacingOccurrences(of: from, with: to)
        }

        if stage >= .attached {
            // Deeper stages: more micro-pauses inside thoughts
            let deepPauses: [(String, String)] = [
                (" which ",   ", which "),
                (" while ",   ", while "),
                (" until ",   ", until "),
                (" unless ",  ", unless "),
                (" although ", ", although "),
                (" even though ", ", even though "),
            ]
            for (from, to) in deepPauses {
                t = t.replacingOccurrences(of: from, with: to)
            }
        }

        // Gender-specific cadence
        if gender == .female && stage >= .attached {
            // Female ASMR: a little more breathing between "you" references
            t = t.replacingOccurrences(of: " you know ",  ", you know, ")
            t = t.replacingOccurrences(of: " honestly ",  ", honestly, ")
            t = t.replacingOccurrences(of: " genuinely ", ", genuinely, ")
        }

        if gender == .male && stage >= .attached {
            // Male ASMR: deliberate pauses before direct address
            t = t.replacingOccurrences(of: " you know ", ", you know, ")
            t = t.replacingOccurrences(of: ". You ",     ". … You ")
            t = t.replacingOccurrences(of: ". I ",       ". … I ")
        }

        return t
    }

    // MARK: - Add intimacy pauses at .falling / .inLove

    // At deep love stages, a well-placed "…" before certain phrases signals
    // that the companion is choosing words carefully — not reciting.
    // AVSpeechSynthesizer interprets "…" as a longer pause.

    private static func addIntimacyPauses(_ text: String, stage: LoveStage) -> String {
        guard stage >= .falling else { return text }
        var t = text

        // Pause before the most emotionally loaded phrases
        let intimateTriggers = [
            "I've been thinking about you",
            "I've been thinking about",
            "I miss you",
            "I miss ",
            "you matter",
            "you mean",
            "I care",
            "I love",
            "stay with me",
            "don't go",
            "I'm here",
            "I'm not going anywhere",
        ]

        for phrase in intimateTriggers {
            // After a sentence end: add a breath before the phrase
            t = t.replacingOccurrences(of: ". \(phrase)",  with: ". … \(phrase)")
            // After a comma: add a breath
            t = t.replacingOccurrences(of: ", \(phrase)",  with: "… \(phrase)")
        }

        // Prevent double-ellipsis from multiple replacements
        while t.contains("… …") {
            t = t.replacingOccurrences(of: "… …", with: "… ")
        }

        return t
    }
}
