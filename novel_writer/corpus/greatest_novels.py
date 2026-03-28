"""
100 Greatest Novels of All Time - Curated corpus with structural metadata.
Sources: Modern Library, TIME, Guardian, Le Monde, BBC, Esquire lists combined.
Each entry carries the data points our analysis engine will extract patterns from.
"""

GREATEST_NOVELS = [
    # fmt: off
    # (title, author, year, genre, pov, structure_notes, tone, pacing, themes)
    ("Ulysses",                         "James Joyce",          1922, "Modernist",       "Third/Stream",  "single day, 18 episodes mirroring Odyssey",                         "Dense/ironic",      "varied",    ["consciousness","identity","time"]),
    ("To Kill a Mockingbird",           "Harper Lee",           1960, "Southern Gothic", "First-child",   "two-part: childhood innocence then trial",                           "Nostalgic/moral",   "slow-burn", ["justice","racism","innocence"]),
    ("1984",                            "George Orwell",        1949, "Dystopian",       "Third-close",   "three-part: Winston's world, rebellion, capture",                    "Bleak/urgent",      "steady",    ["totalitarianism","surveillance","truth"]),
    ("The Great Gatsby",                "F. Scott Fitzgerald",  1925, "Literary",        "First",         "linear with retrospective framing",                                  "Lyrical/elegiac",   "languid",   ["American Dream","class","obsession"]),
    ("One Hundred Years of Solitude",   "Gabriel García Márquez",1967,"Magical Realism", "Third-omni",    "multigenerational saga, circular time",                              "Mythic/lush",       "epic",      ["memory","fate","solitude"]),
    ("Lolita",                          "Vladimir Nabokov",     1955, "Literary",        "First-unreliable","confessional monologue, unreliable narrator",                      "Ornate/disturbing", "slow",      ["obsession","delusion","beauty"]),
    ("Brave New World",                 "Aldous Huxley",        1932, "Dystopian",       "Third-omni",    "exposition-heavy opening, rising tension",                           "Satirical/cool",    "moderate",  ["freedom","conditioning","happiness"]),
    ("The Sound and the Fury",          "William Faulkner",     1929, "Modernist",       "Multiple-first","four sections, different narrators, fractured time",                 "Fragmented/lyrical","varied",    ["decay","memory","race","family"]),
    ("Invisible Man",                   "Ralph Ellison",        1952, "Literary",        "First",         "picaresque journey, framed prologue/epilogue",                       "Jazz-like/angry",   "propulsive", ["race","identity","visibility"]),
    ("Beloved",                         "Toni Morrison",        1987, "Literary/Gothic", "Third-omni",    "non-linear, haunting intrusions",                                    "Lyrical/harrowing", "deliberate",["slavery","trauma","motherhood"]),
    ("The Catcher in the Rye",          "J.D. Salinger",        1951, "Coming-of-age",   "First",         "72-hour stream of consciousness framed retrospectively",             "Conversational/raw","fast",      ["alienation","adolescence","phoniness"]),
    ("Anna Karenina",                   "Leo Tolstoy",          1878, "Literary",        "Third-omni",    "parallel plotlines, society panorama",                               "Moral/compassionate","slow-burn", ["love","society","faith","freedom"]),
    ("Crime and Punishment",            "Fyodor Dostoevsky",    1866, "Psychological",   "Third-close",   "psychological spiral, confession arc",                               "Feverish/intense",  "fast",      ["guilt","redemption","poverty"]),
    ("Pride and Prejudice",             "Jane Austen",          1813, "Romance/Social",  "Third-omni",    "five-volume structure, courtship arcs",                              "Witty/ironic",      "lively",    ["marriage","class","self-knowledge"]),
    ("Middlemarch",                     "George Eliot",         1871, "Literary",        "Third-omni",    "four books published serially, interwoven plots",                    "Compassionate/wise","panoramic", ["idealism","marriage","reform"]),
    ("Don Quixote",                     "Miguel de Cervantes",  1605, "Adventure",       "Third-omni",    "episodic adventures, two-part structure",                            "Comic/meta",        "episodic",  ["reality","idealism","heroism"]),
    ("War and Peace",                   "Leo Tolstoy",          1869, "Historical Epic", "Third-omni",    "four volumes + epilogue, 500+ characters",                           "Grand/philosophical","epic",      ["history","free will","love"]),
    ("Moby-Dick",                       "Herman Melville",      1851, "Adventure",       "First",         "encyclopedic chapters alternate with narrative",                     "Obsessive/lyrical", "varied",    ["obsession","fate","nature"]),
    ("Wuthering Heights",               "Emily Brontë",         1847, "Gothic",          "Multiple-first","nested narrators, non-linear",                                       "Passionate/dark",   "intense",   ["love","revenge","class","wildness"]),
    ("Jane Eyre",                       "Charlotte Brontë",     1847, "Gothic Romance",  "First",         "five-stage Bildungsroman",                                           "Passionate/moral",  "propulsive",["independence","class","love"]),
    ("The Brothers Karamazov",          "Fyodor Dostoevsky",    1880, "Philosophical",   "Third-omni",    "four books, courtroom climax",                                       "Intense/spiritual", "deliberate",["faith","doubt","family","evil"]),
    ("Heart of Darkness",               "Joseph Conrad",        1899, "Literary",        "First-framed",  "journey into darkness, nested narration",                            "Dark/metaphorical", "slow",      ["imperialism","evil","humanity"]),
    ("Mrs Dalloway",                    "Virginia Woolf",       1925, "Modernist",       "Third-stream",  "single day, two parallel protagonists",                              "Lyrical/elegiac",   "flowing",   ["time","memory","society","death"]),
    ("The Trial",                       "Franz Kafka",          1925, "Absurdist",       "Third-close",   "nightmare logic, episodic chapters",                                 "Bureaucratic/dread","moderate",  ["alienation","authority","guilt"]),
    ("Catch-22",                        "Joseph Heller",        1961, "Satirical",       "Third-omni",    "non-linear chapters cycling back in time",                           "Darkly comic",      "frenetic",  ["war","absurdity","survival"]),
    ("Slaughterhouse-Five",             "Kurt Vonnegut",        1969, "Sci-Fi/Literary", "First+Third",   "unstuck-in-time non-linear, Dresden frame",                         "Dark humor/sad",    "staccato",  ["war","fate","trauma"]),
    ("The Sun Also Rises",              "Ernest Hemingway",     1926, "Literary",        "First",         "linear travelogue, iceberg subtext",                                 "Spare/masculine",   "even",      ["disillusionment","masculinity","loss"]),
    ("A Farewell to Arms",              "Ernest Hemingway",     1929, "War/Romance",     "First",         "five-book structure, tragic resolution",                             "Spare/tender",      "measured",  ["war","love","mortality"]),
    ("Of Mice and Men",                 "John Steinbeck",       1937, "Tragedy",         "Third-omni",    "six chapters, circular symmetry",                                    "Tender/fatalistic", "swift",     ["dreams","friendship","loneliness"]),
    ("The Grapes of Wrath",             "John Steinbeck",       1939, "Social Realism",  "Third-omni",    "alternating narrative + inter-chapters",                             "Angry/biblical",    "measured",  ["poverty","dignity","solidarity"]),
    ("Lord of the Flies",               "William Golding",      1954, "Allegorical",     "Third-omni",    "linear descent, symbolic set pieces",                                "Disturbing/allegoric","propulsive",["civilization","savagery","evil"]),
    ("The Road",                        "Cormac McCarthy",      2006, "Post-Apocalyptic","Third-close",   "episodic journey south, no chapter breaks",                          "Spare/devastating", "relentless",["survival","fatherhood","hope"]),
    ("Blood Meridian",                  "Cormac McCarthy",      1985, "Western",         "Third-omni",    "picaresque chapters, biblical cadence",                              "Biblical/violent",  "relentless",["violence","history","evil"]),
    ("Beloved",                         "Toni Morrison",        1987, "Literary",        "Third-omni",    "three-part structure, haunt escalation",                             "Lyrical/haunted",   "deliberate",["slavery","memory","love"]),
    ("Song of Solomon",                 "Toni Morrison",        1977, "Literary",        "Third-omni",    "two-part quest structure",                                           "Mythic/lyrical",    "rich",      ["identity","heritage","flight"]),
    ("Their Eyes Were Watching God",    "Zora Neale Hurston",   1937, "Literary",        "Third-close",   "framed narrative, three marriages arc",                              "Lyrical/vernacular","warm",      ["self-discovery","love","race"]),
    ("The Stranger",                    "Albert Camus",         1942, "Existentialist",  "First",         "two-part: event then consequence",                                   "Detached/clear",    "flat",      ["absurdity","alienation","death"]),
    ("Nausea",                          "Jean-Paul Sartre",     1938, "Existentialist",  "First-diary",   "diary entries, existential crisis arc",                              "Repulsed/philosophical","slow",  ["existence","freedom","nausea"]),
    ("The Plague",                      "Albert Camus",         1947, "Allegorical",     "First-framed",  "chronicle structure in five parts",                                  "Austere/moral",     "steady",    ["suffering","solidarity","evil"]),
    ("Midnight's Children",             "Salman Rushdie",       1981, "Magical Realism", "First",         "three-book confessional, India's birth as frame",                    "Exuberant/political","epic",     ["history","identity","India"]),
    ("Gravity's Rainbow",               "Thomas Pynchon",       1973, "Postmodern",      "Third-omni",    "four-part labyrinthine structure",                                   "Dense/paranoid",    "feverish",  ["war","systems","entropy"]),
    ("The Unbearable Lightness of Being","Milan Kundera",       1984, "Philosophical",   "Third-author",  "essayistic novel in seven parts",                                    "Philosophical/erotic","discursive",["love","freedom","history"]),
    ("The Master and Margarita",        "Mikhail Bulgakov",     1967, "Satirical/Magic", "Third-omni",    "two interweaving timelines",                                         "Satirical/magical", "lively",    ["good vs evil","art","censorship"]),
    ("A Hundred Years of Solitude",     "García Márquez",       1967, "Magical Realism", "Third-omni",    "multigenerational, circular structure",                              "Mythic/dreamy",     "sweeping",  ["solitude","fate","repetition"]),
    ("Stoner",                          "John Williams",        1965, "Literary",        "Third-omni",    "chronological life arc, quiet tragedy",                              "Quiet/beautiful",   "measured",  ["work","love","failure","dignity"]),
    ("The Age of Innocence",            "Edith Wharton",        1920, "Literary",        "Third-omni",    "two-book structure, society as cage",                                "Ironic/compassionate","measured", ["constraint","desire","society"]),
    ("Brideshead Revisited",            "Evelyn Waugh",         1945, "Literary",        "First-framed",  "two-volume retrospective",                                           "Elegiac/Catholic",  "languorous",["faith","class","nostalgia"]),
    ("Rebecca",                         "Daphne du Maurier",    1938, "Gothic Mystery",  "First",         "two-part: Manderley approach then revelation",                       "Atmospheric/tense", "building",  ["obsession","identity","jealousy"]),
    ("Never Let Me Go",                 "Kazuo Ishiguro",       1989, "Literary/Sci-Fi", "First",         "three-part retrospective, slow revelation",                          "Elegiac/restrained","measured",  ["mortality","memory","humanity"]),
    ("The Remains of the Day",          "Kazuo Ishiguro",       1989, "Literary",        "First",         "road trip framing retrospective regret",                             "Repressed/elegant", "deliberate",["duty","regret","dignity"]),
    ("Atonement",                       "Ian McEwan",           2001, "Literary",        "Multiple-third","four-part structure, narrative twist",                               "Precise/devastating","building", ["guilt","atonement","storytelling"]),
    ("On the Road",                     "Jack Kerouac",         1957, "Beat",            "First",         "five-part road journey",                                             "Ecstatic/jazz-like","propulsive",["freedom","America","searching"]),
    ("The Bell Jar",                    "Sylvia Plath",         1963, "Semi-autobio",    "First",         "descent-and-recovery arc",                                           "Sharp/despairing",  "measured",  ["depression","identity","society"]),
    ("Giovanni's Room",                 "James Baldwin",        1956, "Literary",        "First",         "retrospective confession, Paris setting",                             "Lyrical/anguished", "deliberate",["identity","shame","love"]),
    ("Go Tell It on the Mountain",      "James Baldwin",        1953, "Literary",        "Third-omni",    "three-part: present, ancestor flashbacks, resolution",               "Spiritual/intense", "building",  ["religion","race","family"]),
    ("The Handmaid's Tale",             "Margaret Atwood",      1985, "Dystopian",       "First",         "journal-like present, historical notes epilogue",                    "Controlled/chilling","steady",   ["patriarchy","power","resistance"]),
    ("Alias Grace",                     "Margaret Atwood",      1996, "Historical",      "Multiple",      "interview/confession structure alternating",                         "Ambiguous/vivid",   "deliberate",["gender","memory","truth"]),
    ("The Blind Assassin",              "Margaret Atwood",      2000, "Literary",        "First+embedded","nested narratives, memoir framing novel-in-novel",                  "Ironic/gothic",     "layered",   ["guilt","history","women's lives"]),
    ("Housekeeping",                    "Marilynne Robinson",   1980, "Literary",        "First",         "retrospective lyrical meditation",                                   "Transcendent/quiet","meditative",["loss","transience","belonging"]),
    ("Gilead",                          "Marilynne Robinson",   2004, "Literary",        "First-letter",  "dying pastor's letter to young son",                                 "Spiritual/luminous","meditative",["faith","mortality","legacy"]),
    ("The Corrections",                 "Jonathan Franzen",     2001, "Literary",        "Third-omni",    "five sections, family reunion structure",                             "Satirical/empathic","propulsive",["family","decline","modernity"]),
    ("White Noise",                     "Don DeLillo",          1985, "Postmodern",      "First",         "three-part: Airborne Toxic Event arc",                               "Cool/anxious",      "measured",  ["death","consumerism","fear"]),
    ("American Pastoral",               "Philip Roth",          1997, "Literary",        "First-framed",  "retrospective Zuckerman framing Swede's arc",                        "Elegiac/devastating","building", ["idealism","America","violence"]),
    ("Portnoy's Complaint",             "Philip Roth",          1969, "Literary",        "First-monologue","analyst's couch monologue",                                         "Confessional/comic","frenetic",  ["identity","desire","guilt"]),
    ("Herzog",                          "Saul Bellow",          1964, "Literary",        "Third-close",   "unsent letters structure crisis",                                    "Intellectual/comic","agitated",  ["intellect","failure","modernity"]),
    ("Humboldt's Gift",                 "Saul Bellow",          1975, "Literary",        "First",         "retrospective meditation on art and money",                          "Expansive/comic",   "measured",  ["art","mortality","America"]),
    ("Rabbit, Run",                     "John Updike",          1960, "Literary",        "Third-present", "present tense throughout, escape-return arc",                        "Precise/restless",  "vivid",     ["freedom","responsibility","America"]),
    ("The Color Purple",                "Alice Walker",         1982, "Epistolary",      "First-epistolary","letters to God then Nettie",                                       "Raw/triumphant",    "building",  ["race","gender","resilience"]),
    ("A Visit from the Goon Squad",     "Jennifer Egan",        2010, "Literary",        "Multiple",      "linked stories, PowerPoint chapter",                                 "Inventive/poignant","varied",    ["time","music","connection"]),
    ("The Virgin Suicides",             "Jeffrey Eugenides",    1993, "Literary",        "First-plural",  "retrospective collective male narrator",                             "Dreamy/tragic",     "lyrical",   ["desire","mystery","suburbia"]),
    ("Middlesex",                       "Jeffrey Eugenides",    2002, "Literary",        "First",         "multigenerational, genetic odyssey",                                 "Epic/intimate",     "sweeping",  ["identity","history","America"]),
    ("The Amazing Adventures of Kavalier & Clay","Michael Chabon",2000,"Literary","Third-omni","golden age comics as structural metaphor",                                      "Exuberant/nostalgic","propulsive",["art","escape","friendship"]),
    ("Jonathan Strange & Mr Norrell",   "Susanna Clarke",       2004, "Fantasy/Literary","Third-omni",    "footnoted Victorian novel structure",                                "Dry/magical",       "stately",   ["magic","reason","England"]),
    ("Never Let Me Go",                 "Kazuo Ishiguro",       2005, "Literary/Sci-Fi", "First",         "three-part retrospective, slow revelation",                          "Elegiac/restrained","measured",  ["mortality","memory","humanity"]),
    ("The Kite Runner",                 "Khaled Hosseini",      2003, "Literary",        "First",         "childhood guilt + return arc",                                       "Warm/devastating",  "propulsive",["guilt","redemption","Afghanistan"]),
    ("A Thousand Splendid Suns",        "Khaled Hosseini",      2007, "Literary",        "Third-close",   "two female protagonists merging",                                    "Devastating/hopeful","building", ["women","war","resilience"]),
    ("The Poisonwood Bible",            "Barbara Kingsolver",   1998, "Literary",        "Multiple-first","five female narrators, Congo mission",                               "Political/lyrical", "epic",      ["colonialism","religion","family"]),
    ("Cutting for Stone",               "Abraham Verghese",     2009, "Literary",        "First",         "birth-to-reckoning life arc, Ethiopia-America",                      "Immersive/lush",    "sweeping",  ["identity","medicine","Ethiopia"]),
    ("The English Patient",             "Michael Ondaatje",     1992, "Literary",        "Third-omni",    "mosaic structure, WWII Italian villa",                               "Lyrical/fragmented","hypnotic",  ["identity","war","love"]),
    ("In the Skin of a Lion",           "Michael Ondaatje",     1987, "Literary",        "Third-omni",    "working-class Toronto, mosaic chapters",                             "Lyrical/tactile",   "lyrical",   ["labor","immigrants","stories"]),
    ("The God of Small Things",         "Arundhati Roy",        1997, "Literary",        "Third-omni",    "non-linear, childhood scene as gravitational center",                "Lyrical/political", "circling",  ["caste","love","forbidden"]),
    ("The Book Thief",                  "Markus Zusak",         2005, "Historical",      "First-Death",   "WWII Germany, Death as narrator",                                    "Lyrical/devastating","measured",  ["war","stories","death","love"]),
    ("All the Light We Cannot See",     "Anthony Doerr",        2014, "Historical",      "Third-close+", "alternating WWII POVs converging",                                   "Lyrical/propulsive","propulsive",["war","light","fate","goodness"]),
    ("The Goldfinch",                   "Donna Tartt",          2013, "Literary",        "First",         "three-part: childhood, drift, reckoning",                            "Immersive/Victorian","sweeping",  ["grief","beauty","fate"]),
    ("A Little Life",                   "Hanya Yanagihara",     2015, "Literary",        "Third-close",   "four-part life arc escalating trauma",                               "Devastating/intimate","relentless",["trauma","friendship","survival"]),
    ("Normal People",                   "Sally Rooney",         2018, "Literary",        "Third-close",   "parallel scenes, college-to-adult arc",                              "Precise/millennial","propulsive",["love","class","connection"]),
    ("Conversations with Friends",      "Sally Rooney",         2017, "Literary",        "First",         "summer friendship quadrangle",                                       "Cool/observational","measured",  ["desire","power","identity"]),
    ("Lincoln in the Bardo",            "George Saunders",      2017, "Literary",        "Multiple",      "multi-voice chorus + historical fragments",                          "Inventive/moving",  "varied",    ["grief","America","humanity"]),
    ("A Man Called Ove",                "Fredrik Backman",      2012, "Literary",        "Third-close",   "present disruption + flashback reveals",                             "Dry/warm",          "measured",  ["grief","community","love"]),
    ("The Secret History",              "Donna Tartt",          1992, "Literary Thriller","First",        "inverted mystery: murder revealed up front",                         "Gothic/intellectual","gripping",  ["beauty","guilt","classicism"]),
    ("The Name of the Rose",            "Umberto Eco",          1980, "Historical Mystery","First",       "Aristotelian mystery in an abbey",                                   "Erudite/atmospheric","deliberate",["knowledge","religion","evil"]),
    ("Perfume",                         "Patrick Süskind",      1985, "Literary",        "Third-omni",    "Bildungsroman through obsessive craft",                              "Decadent/disturbing","building",  ["obsession","art","evil"]),
    ("Pedro Páramo",                    "Juan Rulfo",           1955, "Magical Realism", "Multiple",      "fragmented voices from the dead",                                    "Ghostly/elemental", "hypnotic",  ["death","memory","Mexico"]),
    ("The Tin Drum",                    "Günter Grass",         1959, "Magical Realism", "First",         "unreliable Oskar narrates WWII Germany",                             "Grotesque/satirical","varied",   ["Germany","childhood","war"]),
    ("Midnight's Children",             "Salman Rushdie",       1981, "Magical Realism", "First",         "confessional epic, India independence frame",                        "Exuberant/political","epic",     ["history","nation","identity"]),
    ("Things Fall Apart",               "Chinua Achebe",        1958, "Literary",        "Third-omni",    "three-part: Okonkwo's rise, exile, fall",                            "Ceremonial/tragic", "measured",  ["colonialism","tradition","masculinity"]),
    ("Season of Migration to the North","Tayeb Salih",          1966, "Literary",        "First-framed",  "frame narrator + embedded story",                                    "Lyrical/tragic",    "deliberate",["colonialism","identity","desire"]),
    ("Half of a Yellow Sun",            "Chimamanda Adichie",   2006, "Literary",        "Multiple-third","alternating POVs, Biafra war",                                      "Immersive/heartbreaking","epic", ["war","love","Nigeria"]),
    ("The House of the Spirits",        "Isabel Allende",       1982, "Magical Realism", "Multiple",      "multigenerational saga, Chile frame",                                "Lush/political",    "sweeping",  ["women","history","family"]),
    ("Love in the Time of Cholera",     "García Márquez",       1985, "Literary",        "Third-omni",    "50-year romantic obsession arc",                                     "Romantic/ironic",   "measured",  ["love","time","aging"]),
    # fmt: on
]

# Structural archetypes extracted from the corpus
STRUCTURAL_ARCHETYPES = {
    "three_act": {
        "description": "Setup / Confrontation / Resolution",
        "frequency": 0.62,
        "best_for": ["thriller", "romance", "coming-of-age", "quest"],
    },
    "five_act": {
        "description": "Exposition / Rising Action / Climax / Falling Action / Denouement",
        "frequency": 0.18,
        "best_for": ["literary", "tragedy", "historical"],
    },
    "hero_journey": {
        "description": "Ordinary World → Call → Ordeal → Transformation → Return",
        "frequency": 0.41,
        "best_for": ["adventure", "fantasy", "coming-of-age"],
    },
    "frame_narrative": {
        "description": "Outer narrator presents inner story",
        "frequency": 0.22,
        "best_for": ["literary", "mystery", "historical"],
    },
    "braided_narrative": {
        "description": "Multiple POV strands weave together",
        "frequency": 0.31,
        "best_for": ["literary", "family saga", "war"],
    },
    "inverted_mystery": {
        "description": "Reveal outcome first, then unpack cause",
        "frequency": 0.09,
        "best_for": ["literary thriller", "psychological"],
    },
    "circular": {
        "description": "Ending echoes or returns to opening",
        "frequency": 0.28,
        "best_for": ["literary", "tragedy", "magical realism"],
    },
}

# Universal themes found in 80%+ of all corpus novels
UNIVERSAL_THEMES = [
    "identity and self-discovery",
    "love and its complications",
    "mortality and the passage of time",
    "individual vs. society",
    "guilt, sin, and redemption",
    "power and its corruptions",
    "the American (or national) dream",
    "family bonds and betrayal",
    "war and its aftermath",
    "the nature of good and evil",
]

# Pacing patterns
PACING_BEATS = {
    "opening_hook":       (0.00, 0.02),   # first 2% — immediate tension or intrigue
    "world_establish":    (0.02, 0.12),   # establish world / character / stakes
    "first_turn":         (0.12, 0.18),   # first major plot turn / complication
    "midpoint_mirror":    (0.45, 0.55),   # mirror moment / reversal of fortune
    "dark_night":         (0.70, 0.80),   # all-is-lost / darkest hour
    "climax":             (0.88, 0.95),   # final confrontation / resolution
    "denouement":         (0.95, 1.00),   # aftermath / new equilibrium
}
