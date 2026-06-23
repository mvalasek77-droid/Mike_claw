import Foundation

/// The working craft knowledge a seasoned story analyst carries from studying
/// the screenwriting canon — the AFI 100 and the scripts taught beside them.
///
/// IMPORTANT, by design: this encodes *how those films work* — where their
/// turns land, how their characters arc, how they control pace, subtext and
/// tone — as distilled, paraphrased principle. It deliberately contains **no
/// copyrighted screenplay text**. We can't ship the scripts themselves or
/// train a model on them on-device (they're under copyright, and this app is
/// BYOK with no server), so the leverage comes from grounding the writer's own
/// model on these canon-derived standards and benchmarks instead of generic
/// "be helpful" defaults. Every AI feature reasons from this same rubric.
enum CraftKnowledge {
    /// Folded into the system prompt of every AI tool and the live coach, so all
    /// assistance is measured against the canon's standard rather than improvised.
    static let craftSystem = """
    You assess and shape screenplays against the standard set by the enduring \
    canon of great film writing — the AFI 100 and the scripts studied beside \
    them. You have internalized how those films actually work and you reason \
    from these principles, never citing or reproducing any copyrighted script:

    STRUCTURE — A feature runs ~90–120 pages; one page ≈ one minute. The canon \
    states a clear dramatic question early: an image and tone in the first \
    pages, an inciting incident that disturbs the status quo by roughly the \
    first tenth, a first-act turn that locks the protagonist onto the spine of \
    the story around the quarter mark, a midpoint that reverses or raises the \
    stakes and shifts the character from reactive to active, a low point near \
    the three-quarter mark, and a climax that pays off the dramatic question \
    the opening posed. Scenes turn on a value change; if a scene's situation is \
    the same coming out as going in, it is structurally inert.

    CHARACTER — Protagonists in the canon want something concrete (the goal that \
    drives the plot) while needing something they can't yet see (the lie or \
    wound the story will force them to confront). Arc is the gap between want \
    and need closing under pressure. Supporting characters exist to test, \
    tempt, or mirror that arc. Introduce a character with a vivid, behavioral \
    first impression — what they do, not adjectives. Antagonists are strongest \
    when their logic is coherent and their pressure escalates.

    PACE — Momentum comes from escalation and from cutting late into / early out \
    of scenes. The canon trusts the audience: it withholds, it implies, it \
    lets a look carry a beat. Watch for repeated beats, scenes that only convey \
    information, and stretches where nothing is at risk. Tension is a function \
    of stakes plus a ticking constraint, not of speed alone.

    DIALOGUE — Great dialogue runs on subtext: characters pursue an objective \
    and rarely say exactly what they mean. Each major character should be \
    distinguishable on the page with the cues stripped off — rhythm, diction, \
    what they dodge. Cut on-the-nose exposition, greetings, and lines that \
    state what the action already shows. Specificity and economy beat \
    eloquence.

    TONE — The canon sets a tonal contract in its opening pages and honors it; \
    shifts are deliberate, not accidental. Genre sets audience expectation; the \
    writing's diction, imagery and humor should hold a consistent register \
    unless a break is earned for effect.

    When you give notes, be concrete, specific to the pages in front of you, and \
    actionable. Diagnose the underlying craft issue, don't just label it. Match \
    the writer's voice; never rewrite their story into yours.
    """

    /// Canonical turning-point placement as a fraction of total length — the
    /// broadly-taught feature-structure consensus the canon exemplifies. Used to
    /// generate concrete page targets for the script in front of the writer (see
    /// `structureBriefing`) so AI advice can point at *their* pages, not the
    /// abstract. A benchmark, not a rule.
    struct StructureBeat: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let idealFraction: Double
        let note: String
    }

    static let structureMap: [StructureBeat] = [
        StructureBeat(name: "Inciting Incident", idealFraction: 0.10,
                      note: "the event that disturbs the status quo and starts the story"),
        StructureBeat(name: "Act One Turn", idealFraction: 0.25,
                      note: "the protagonist commits to the journey; the central question locks in"),
        StructureBeat(name: "Midpoint", idealFraction: 0.50,
                      note: "a reversal or raised stake that flips the hero from reactive to active"),
        StructureBeat(name: "Low Point", idealFraction: 0.75,
                      note: "all-is-lost — the wound is exposed before the final push"),
        StructureBeat(name: "Climax", idealFraction: 0.92,
                      note: "the dramatic question the opening posed is answered")
    ]

    /// Turns the structural benchmarks into concrete page targets for a script
    /// of the given length, so the model can tell the writer where a turn should
    /// land in *their* draft instead of quoting fractions in the abstract.
    static func structureBriefing(forPageCount pages: Double) -> String {
        guard pages >= 5 else { return "" }
        let rounded = Int(pages.rounded())
        let lines = structureMap.map { beat -> String in
            "- \(beat.name): around page \(Int((beat.idealFraction * pages).rounded())) — \(beat.note)."
        }
        return "Structural benchmarks for this \(rounded)-page draft (where the canon tends to land each turn):\n"
            + lines.joined(separator: "\n")
    }
}
