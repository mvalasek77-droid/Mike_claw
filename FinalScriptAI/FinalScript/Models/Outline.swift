import Foundation

/// A reusable story-structure template. Selecting one seeds the beat board
/// with the template's named beats placed in the right acts — the same
/// jump-start Arc Studio offers, plus a couple of extras.
struct StructureTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let blurb: String
    let acts: [ActColumn]
    /// Beat title + summary + act number, in order.
    let seeds: [(title: String, summary: String, act: Int)]

    static func == (lhs: StructureTemplate, rhs: StructureTemplate) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Materialize the template's seeds into beats for a fresh board.
    func makeBeats() -> [Beat] {
        seeds.enumerated().map { index, seed in
            Beat(title: seed.title, summary: seed.summary, act: seed.act, order: index,
                 colorTag: .amber)
        }
    }
}

enum StructureLibrary {
    static let threeAct = StructureTemplate(
        id: "three-act",
        name: "Three-Act",
        blurb: "The classic setup / confrontation / resolution spine.",
        acts: [ActColumn(number: 1, name: "Act I — Setup"),
               ActColumn(number: 2, name: "Act II — Confrontation"),
               ActColumn(number: 3, name: "Act III — Resolution")],
        seeds: [
            ("Opening Image", "Establish tone and the world before change.", 1),
            ("Inciting Incident", "The event that knocks the story into motion.", 1),
            ("First Act Break", "The protagonist commits to the journey.", 1),
            ("Midpoint", "A reversal that raises the stakes.", 2),
            ("Low Point", "All seems lost.", 2),
            ("Climax", "The final confrontation.", 3),
            ("Resolution", "The new normal.", 3)
        ]
    )

    static let saveTheCat = StructureTemplate(
        id: "save-the-cat",
        name: "Save the Cat",
        blurb: "Blake Snyder's 15-beat sheet for tight commercial structure.",
        acts: [ActColumn(number: 1, name: "Act I"),
               ActColumn(number: 2, name: "Act II"),
               ActColumn(number: 3, name: "Act III")],
        seeds: [
            ("Opening Image", "A snapshot of the hero's world.", 1),
            ("Theme Stated", "What the story is really about.", 1),
            ("Set-Up", "Introduce the hero and stakes.", 1),
            ("Catalyst", "The life-changing event.", 1),
            ("Debate", "Should the hero go?", 1),
            ("Break into Two", "The hero chooses the new world.", 2),
            ("B Story", "The relationship that carries the theme.", 2),
            ("Fun and Games", "The promise of the premise.", 2),
            ("Midpoint", "A false victory or defeat.", 2),
            ("Bad Guys Close In", "Pressure mounts.", 2),
            ("All Is Lost", "The lowest point.", 2),
            ("Dark Night of the Soul", "The hero wallows in defeat.", 2),
            ("Break into Three", "The solution appears.", 3),
            ("Finale", "The hero proves change and wins.", 3),
            ("Final Image", "The opposite of the opening image.", 3)
        ]
    )

    static let herosJourney = StructureTemplate(
        id: "heros-journey",
        name: "Hero's Journey",
        blurb: "Campbell's mythic cycle, condensed for the screen.",
        acts: [ActColumn(number: 1, name: "Departure"),
               ActColumn(number: 2, name: "Initiation"),
               ActColumn(number: 3, name: "Return")],
        seeds: [
            ("Ordinary World", "Life before the call.", 1),
            ("Call to Adventure", "A problem or challenge appears.", 1),
            ("Refusal of the Call", "Hesitation and fear.", 1),
            ("Meeting the Mentor", "Guidance and tools.", 1),
            ("Crossing the Threshold", "Committing to the adventure.", 1),
            ("Tests, Allies, Enemies", "Learning the new world's rules.", 2),
            ("Approach", "Preparing for the central ordeal.", 2),
            ("The Ordeal", "Facing the greatest fear.", 2),
            ("Reward", "Seizing the prize.", 2),
            ("The Road Back", "Driven to complete the journey.", 3),
            ("Resurrection", "The final, purifying test.", 3),
            ("Return with the Elixir", "Bringing change home.", 3)
        ]
    )

    static let all: [StructureTemplate] = [threeAct, saveTheCat, herosJourney]
}
