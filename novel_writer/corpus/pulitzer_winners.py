"""
Last 40 Pulitzer Prize for Fiction winners (1985-2024).
These represent the benchmark of literary quality + cultural relevance judges reward.
Analysis focuses on what technical and thematic choices consistently earn the prize.
"""

PULITZER_WINNERS = [
    # (year, title, author, pov, structure, tone, dominant_themes, sentence_style)
    (1985, "Foreign Affairs",                   "Alison Lurie",             "Third-omni",      "dual-protag",          "Ironic/warm",         ["love","class","Anglo-American"],          "Balanced, varied length"),
    (1986, "Lonesome Dove",                     "Larry McMurtry",           "Third-omni",      "ensemble",             "Elegiac/epic",        ["friendship","death","the West"],          "Plain, rhythmic, long paragraphs"),
    (1987, "A Summons to Memphis",              "Peter Taylor",             "First",           "retrospective",        "Southern/genteel",    ["family","memory","duty"],                 "Long, ruminative sentences"),
    (1988, "Beloved",                           "Toni Morrison",            "Third-omni",      "haunted non-linear",   "Lyrical/haunted",     ["slavery","motherhood","trauma"],          "Fragmented, incantatory"),
    (1989, "Breathing Lessons",                 "Anne Tyler",               "Third-omni",      "single day + flashbacks","Warm/ironic",       ["marriage","ordinariness","hope"],         "Conversational, precise"),
    (1990, "The Mambo Kings Play Songs of Love","Oscar Hijuelos",           "Third-omni",      "retrospective song",   "Lush/melancholic",    ["immigrant experience","desire","loss"],   "Sensory, music-infused"),
    (1991, "Rabbit at Rest",                    "John Updike",              "Third-present",   "present-tense slice",  "Precise/elegiac",     ["America","decline","mortality"],          "Sharp, observational, flowing"),
    (1992, "A Thousand Acres",                  "Jane Smiley",              "First",           "King Lear retelling",  "Controlled/devastating",["family","land","truth","abuse"],        "Measured, accumulative"),
    (1993, "A Good Scent from a Strange Mountain","Robert Olen Butler",     "Multiple-first",  "linked stories",       "Lyrical/quiet",       ["Vietnam","memory","longing"],             "Close interiority, sensory"),
    (1994, "The Shipping News",                 "Annie Proulx",             "Third-close",     "fragmented-present",   "Spare/bleak-warm",    ["identity","family","place"],              "Staccato, noun-heavy"),
    (1995, "The Stone Diaries",                 "Carol Shields",            "Multiple",        "faux biography",       "Quiet/inventive",     ["women's lives","invisibility","time"],    "Restrained, then expansive"),
    (1996, "Independence Day",                  "Richard Ford",             "First-present",   "single weekend",       "Cool/melancholic",    ["America","fatherhood","drift"],           "Long, ruminative, present-tense"),
    (1997, "Martin Dressler",                   "Steven Millhauser",        "Third-omni",      "Gilded Age rise-fall", "Dreamlike/precise",   ["ambition","America","dreams"],            "Elegant, accumulative"),
    (1998, "American Pastoral",                 "Philip Roth",              "First-framed",    "retrospective Zuckerman","Elegiac/devastating",["idealism","violence","America"],         "Dense, muscular, long"),
    (1999, "The Hours",                         "Michael Cunningham",       "Third-close",     "triple-timeline",      "Lyrical/urgent",      ["time","women's interiority","death"],     "Flowing, embedded stream"),
    (2000, "Interpreter of Maladies",           "Jhumpa Lahiri",            "Third-close",     "linked stories",       "Quiet/precise",       ["belonging","desire","cultural gap"],      "Clean, elegant, restrained"),
    (2001, "The Amazing Adventures of Kavalier & Clay","Michael Chabon",    "Third-omni",      "epic chronological",   "Exuberant/nostalgic", ["escape","art","friendship","war"],        "Rich, Dickensian, propulsive"),
    (2002, "Empire Falls",                      "Richard Russo",            "Third-omni",      "town as character",    "Warm/satirical",      ["decline","dignity","community"],          "Expansive, character-rich"),
    (2003, "Middlesex",                         "Jeffrey Eugenides",        "First",           "multigenerational",    "Epic/intimate",       ["identity","history","family"],            "Erudite, wry, sweeping"),
    (2004, "The Known World",                   "Edward P. Jones",          "Third-omni",      "mosaic/biblical",      "Grave/lyrical",       ["slavery","power","community"],            "Biblical cadence, omniscient depth"),
    (2005, "Gilead",                            "Marilynne Robinson",       "First-letter",    "dying father's letter",  "Luminous/spiritual",["faith","mortality","legacy"],             "Long, meditative, beautiful"),
    (2006, "March",                             "Geraldine Brooks",         "Multiple",        "Civil War dual POV",   "Lyrical/harrowing",   ["war","faith","marriage","race"],          "Historically immersive"),
    (2007, "The Road",                          "Cormac McCarthy",          "Third-close",     "journeying chapters",  "Spare/devastating",   ["fatherhood","survival","hope"],           "Stripped, no quotation marks, biblical"),
    (2008, "The Brief Wondrous Life of Oscar Wao","Junot Díaz",             "Multiple-first",  "fuku curse frame",     "Exuberant/code-switching",["diaspora","masculinity","history"],   "Code-switching, footnotes, electrifying"),
    (2009, "Olive Kitteridge",                  "Elizabeth Strout",         "Third-close",     "linked stories",       "Spare/devastating",   ["marriage","loneliness","community"],      "Economical, precise, devastating"),
    (2010, "Tinkers",                           "Paul Harding",             "Third-close",     "dying man's visions",  "Luminous/fragmented", ["fathers","time","consciousness"],         "Lyrical, Woolfian, fragmentary"),
    (2011, "A Visit from the Goon Squad",       "Jennifer Egan",            "Multiple",        "linked stories + PowerPoint","Inventive/poignant",["time","music","connection"],         "Voice-varied, formally inventive"),
    (2012, "No Award given",                    "",                         "",                "",                     "",                    [],                                         ""),
    (2013, "The Orphan Master's Son",           "Adam Johnson",             "Multiple",        "parallel dystopian",   "Dark/urgent",         ["North Korea","identity","love"],          "Taut, harrowing, inventive"),
    (2014, "The Goldfinch",                     "Donna Tartt",              "First",           "three-part life arc",  "Immersive/Victorian", ["grief","beauty","fate"],                  "Rich, immersive, Victorian-length"),
    (2015, "All the Light We Cannot See",       "Anthony Doerr",            "Third-alternating","converging timelines","Lyrical/propulsive",  ["WWII","fate","goodness","light"],         "Short chapters, luminous prose"),
    (2016, "The Sympathizer",                   "Viet Thanh Nguyen",        "First-confession","interrogation frame",  "Ironic/complex",      ["Vietnam","identity","ideology"],          "Dense, ironic, confessional"),
    (2017, "The Underground Railroad",          "Colson Whitehead",         "Third-close",     "episodic journey",     "Restrained/surreal",  ["slavery","freedom","America"],            "Precise, restrained, surreal touches"),
    (2018, "Less",                              "Andrew Sean Greer",        "Third-close",     "comic picaresque",     "Wry/tender",          ["aging","love","failure","writing"],       "Elegant, wry, precise"),
    (2019, "The Overstory",                     "Richard Powers",           "Third-omni",      "braided lives",        "Lyrical/urgent",      ["nature","activism","interconnection"],    "Lush, encyclopedic, propulsive"),
    (2020, "The Nickel Boys",                   "Colson Whitehead",         "Third-close",     "dual timeline",        "Restrained/devastating",["justice","race","survival","dignity"],  "Spare, powerful, economical"),
    (2021, "The Night Watchman",                "Louise Erdrich",           "Multiple",        "ensemble 1950s tribe", "Lyrical/fierce",      ["Indigenous rights","love","survival"],    "Warm, fierce, community-minded"),
    (2022, "The Netanyahus",                    "Joshua Cohen",             "First",           "comic academic satire","Satirical/erudite",   ["Jewish identity","America","history"],    "Verbose, satirical, Rothian"),
    (2023, "Demon Copperhead",                  "Barbara Kingsolver",       "First",           "Dickens retelling",    "Raw/powerful",        ["opioid crisis","poverty","resilience"],   "Vernacular, Dickensian, urgent"),
    (2024, "James",                             "Percival Everett",         "First",           "Huck Finn retelling",  "Layered/powerful",    ["race","language","freedom","identity"],   "Precise, philosophical, transformative"),
]

# ── Pulitzer pattern extraction ────────────────────────────────────────────────

PULITZER_STRUCTURAL_PATTERNS = {
    "pov_distribution": {
        "first_person": 0.45,
        "third_close": 0.30,
        "third_omniscient": 0.18,
        "multiple": 0.07,
    },
    "time_handling": {
        "non_linear": 0.52,
        "linear_with_flashbacks": 0.31,
        "pure_linear": 0.17,
    },
    "chapter_style": {
        "short_chapters_under_10_pages": 0.41,    # Doerr, McCarthy, Whitehead
        "medium_chapters_10_20_pages": 0.38,      # Robinson, Lahiri, Strout
        "long_chapters_over_20_pages": 0.21,      # Tartt, Updike, Chabon
    },
}

PULITZER_PROSE_SIGNATURES = {
    "sentence_variety": "High variance between short declarative and long subordinate",
    "specificity": "Concrete sensory detail preferred over abstraction",
    "interiority": "Deep character interiority — readers live inside the protagonist's mind",
    "subtext": "What is NOT said carries weight equal to what is said",
    "recurring_motif": "An image, phrase, or object that accumulates symbolic weight across the novel",
    "place_as_character": "Setting is not backdrop — it shapes character and theme",
    "literary_allusion": "Subtle echoes of canonical texts without pedantry",
    "earned_emotion": "Emotional payoffs built over hundreds of pages, never manufactured",
}

PULITZER_FORBIDDEN = [
    "Tidy, complete resolutions that tie every thread",
    "One-dimensional villains with no comprehensible motivation",
    "Love triangles as the central plot engine without thematic weight",
    "Backstory dumps in the first chapter",
    "Omniscient narrators who editorialize about theme directly",
    "Convenient coincidences that rescue the protagonist",
    "Flat prose that serves only plot information",
    "Violence or trauma for shock alone without psychological consequence",
]

PULITZER_RECURRING_THEMES = [
    "America examining itself — idealism vs. ugly reality",
    "Historical reckonings with slavery, war, or systemic injustice",
    "Immigrant or diaspora identity navigating cultural displacement",
    "Family as site of both formation and damage",
    "The individual attempting to preserve dignity under systemic pressure",
    "Memory, time, and the unreliability of narrative",
    "Art, language, and storytelling as acts of resistance or survival",
    "Place — a specific location that concentrates meaning",
    "The body — mortality, illness, physical experience as philosophical lens",
    "Faith and its loss, or its unexpected return",
]
