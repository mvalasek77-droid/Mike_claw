import Foundation

enum SampleData {
    static func starterLibrary() -> [Screenplay] {
        [welcomeScript()]
    }

    static func welcomeScript() -> Screenplay {
        var s = Screenplay(title: "The Last Reel")
        s.genre = "Neo-noir thriller"
        s.logline = "A projectionist who can see the future in film grain has 24 hours to stop a murder he's already watched happen."
        s.titlePage = TitlePage(title: "THE LAST REEL", credit: "Written by",
                                author: "You", source: "", contact: "",
                                draftDate: "First Draft")
        s.elements = [
            ScreenplayElement(type: .sceneHeading, text: "INT. RIALTO CINEMA - PROJECTION BOOTH - NIGHT"),
            ScreenplayElement(type: .action, text: "A cramped booth bathed in flickering amber. MILO REYES (40s), unshaven, watches the beam more than the screen."),
            ScreenplayElement(type: .character, text: "MILO"),
            ScreenplayElement(type: .parenthetical, text: "(to himself)"),
            ScreenplayElement(type: .dialogue, text: "Same frame. Every time."),
            ScreenplayElement(type: .action, text: "He leans into the projector's glow. In the dancing grain — a face. A scream with no sound."),
            ScreenplayElement(type: .sceneHeading, text: "INT. RIALTO CINEMA - LOBBY - CONTINUOUS"),
            ScreenplayElement(type: .action, text: "Empty. A single ticket stub spins on the floor, though no door has opened."),
            ScreenplayElement(type: .character, text: "NADIA"),
            ScreenplayElement(type: .parenthetical, text: "(O.S.)"),
            ScreenplayElement(type: .dialogue, text: "You're closing up late again, Milo."),
            ScreenplayElement(type: .transition, text: "CUT TO:")
        ]
        s.beats = StructureLibrary.threeAct.makeBeats()
        s.characters = [
            CharacterProfile(name: "MILO", role: "Protagonist",
                             description: "A projectionist haunted by what he sees in the film.",
                             voiceNotes: "Clipped, wry, talks to himself. Avoids questions he can answer with a joke.",
                             age: "47", goal: "Stop the murder he keeps seeing."),
            CharacterProfile(name: "NADIA", role: "Ally",
                             description: "Night-shift usher who notices everything.",
                             voiceNotes: "Direct, warm, impatient with Milo's evasions.",
                             age: "29", goal: "Get Milo to trust her.")
        ]
        s.revisions = [Revision(name: "First Draft", colorName: "White")]
        return s
    }
}
