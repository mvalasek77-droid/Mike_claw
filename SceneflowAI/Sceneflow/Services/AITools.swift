import Foundation

/// The catalog of AI assists Sceneflow offers. Each case knows how to build
/// the system prompt and the user prompt for its task from the surrounding
/// screenplay context. Keeping prompt construction here (not scattered through
/// the UI) means the writing behaviour is testable and consistent.
enum AITool: String, CaseIterable, Identifiable {
    case continueScene
    case punchUpDialogue
    case rewriteAction
    case coverageNotes
    case generateLogline
    case generateSynopsis
    case brainstormBeats
    case characterVoice
    case nameSuggestions
    case toneAnalysis

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continueScene: return "Continue Scene"
        case .punchUpDialogue: return "Punch Up Dialogue"
        case .rewriteAction: return "Tighten Action"
        case .coverageNotes: return "Coverage Notes"
        case .generateLogline: return "Generate Logline"
        case .generateSynopsis: return "Write Synopsis"
        case .brainstormBeats: return "Brainstorm Beats"
        case .characterVoice: return "Check Character Voice"
        case .nameSuggestions: return "Suggest Names"
        case .toneAnalysis: return "Analyze Tone"
        }
    }

    var subtitle: String {
        switch self {
        case .continueScene: return "Draft the next few lines in your voice."
        case .punchUpDialogue: return "Sharper, more distinct dialogue."
        case .rewriteAction: return "Lean, vivid stage direction."
        case .coverageNotes: return "An honest reader's script report."
        case .generateLogline: return "A one-sentence hook."
        case .generateSynopsis: return "A tight paragraph summary."
        case .brainstormBeats: return "Story beats for where you're stuck."
        case .characterVoice: return "Flag off-voice lines for a character."
        case .nameSuggestions: return "Character & location name ideas."
        case .toneAnalysis: return "Genre, mood, and pacing read."
        }
    }

    var symbol: String {
        switch self {
        case .continueScene: return "text.append"
        case .punchUpDialogue: return "bubble.left.and.bubble.right.fill"
        case .rewriteAction: return "scissors"
        case .coverageNotes: return "doc.text.magnifyingglass"
        case .generateLogline: return "bolt.fill"
        case .generateSynopsis: return "list.bullet.rectangle.fill"
        case .brainstormBeats: return "lightbulb.fill"
        case .characterVoice: return "waveform"
        case .nameSuggestions: return "person.text.rectangle.fill"
        case .toneAnalysis: return "gauge.with.dots.needle.50percent"
        }
    }

    /// Tools that operate on the whole script vs. the current scene/selection.
    var scope: Scope {
        switch self {
        case .continueScene, .punchUpDialogue, .rewriteAction, .characterVoice:
            return .scene
        case .coverageNotes, .generateLogline, .generateSynopsis, .brainstormBeats,
             .nameSuggestions, .toneAnalysis:
            return .document
        }
    }

    enum Scope { case scene, document }

    static var shared: String {
        // System prompt prefix shared by every tool — establishes the persona
        // and the house rules so output is consistently useful and on-craft.
        """
        You are a professional screenwriting collaborator inside a screenwriting \
        app. You understand industry format (Fountain/Final Draft), story \
        structure, subtext, and character voice. Be concrete and craft-focused. \
        Never lecture. Match the writer's existing tone and voice rather than \
        imposing your own. When you output screenplay text, use correct \
        screenplay format with scene headings in CAPS, character cues in CAPS, \
        and dialogue beneath them.
        """
    }

    func systemPrompt(for screenplay: Screenplay) -> String {
        var prompt = AITool.shared + "\n\n"
        if !screenplay.title.isEmpty { prompt += "Project: \(screenplay.title)\n" }
        if !screenplay.genre.isEmpty { prompt += "Genre: \(screenplay.genre)\n" }
        if !screenplay.logline.isEmpty { prompt += "Logline: \(screenplay.logline)\n" }
        return prompt
    }

    /// Build the user-turn prompt. `context` is the relevant slice of the
    /// script (full document or current scene), already serialized to Fountain.
    func userPrompt(context: String, screenplay: Screenplay, focusCharacter: String?) -> String {
        switch self {
        case .continueScene:
            return """
            Here is the current scene:

            \(context)

            Continue this scene with the next 4–8 lines (action and/or dialogue). \
            Stay in the established voice and momentum. Output only the new \
            screenplay lines, formatted correctly — no commentary.
            """
        case .punchUpDialogue:
            return """
            Here is a passage:

            \(context)

            Rewrite the dialogue to be sharper and more distinct per character, \
            preserving meaning and beats. Keep it the same length or shorter. \
            Output the revised passage in screenplay format, then a short bullet \
            list of what you changed and why.
            """
        case .rewriteAction:
            return """
            Here is a passage:

            \(context)

            Tighten the action/description lines: active verbs, present tense, \
            visual and lean. Cut filler. Output the revised passage in screenplay \
            format.
            """
        case .coverageNotes:
            return """
            Here is the screenplay so far:

            \(context)

            Write professional development coverage: a one-line logline, a \
            STRENGTHS section, a CONCERNS section (structure, character, pacing, \
            dialogue, marketability), and 3 concrete, prioritized next steps. Be \
            honest and specific, like a reader giving notes to a writer they respect.
            """
        case .generateLogline:
            return """
            Based on this material:

            \(context)

            Write 3 distinct loglines (one sentence each) that capture the \
            protagonist, their goal, the central conflict, and the stakes. Number them.
            """
        case .generateSynopsis:
            return """
            Based on this material:

            \(context)

            Write a tight one-paragraph synopsis (about 120 words) in present \
            tense suitable for a query or pitch. Output only the paragraph.
            """
        case .brainstormBeats:
            return """
            Here is the story so far:

            \(context)

            Brainstorm 5 possible next story beats. For each: a one-line title \
            and 1–2 sentences of what happens and why it escalates the conflict. \
            Number them. Offer real range, not variations of one idea.
            """
        case .characterVoice:
            let name = focusCharacter ?? screenplay.characterNames.first ?? "the lead"
            let profile = screenplay.characters.first { $0.name.uppercased() == name.uppercased() }
            let voice = profile?.voiceNotes ?? ""
            return """
            Character: \(name)\(voice.isEmpty ? "" : "\nVoice notes: \(voice)")

            Passage:

            \(context)

            Review every line spoken by \(name). Flag any that feel off-voice or \
            generic, quote them, and suggest an in-voice rewrite for each. If the \
            voice is consistent, say so and explain what's working.
            """
        case .nameSuggestions:
            return """
            Project context:

            \(context)

            Suggest 8 character names and 6 location names that fit this story's \
            world, era, and tone. Group them under CHARACTERS and LOCATIONS. Add \
            a few words of rationale per name.
            """
        case .toneAnalysis:
            return """
            Here is the screenplay:

            \(context)

            Analyze: primary and secondary genre, overall tone/mood, comparable \
            films, pacing (does any stretch drag or rush?), and whether the tone \
            holds consistently. Keep it to a focused half-page.
            """
        }
    }

    var maxTokens: Int {
        switch self {
        case .coverageNotes, .generateSynopsis, .toneAnalysis: return 2000
        case .continueScene, .punchUpDialogue, .rewriteAction: return 1500
        default: return 1200
        }
    }
}
