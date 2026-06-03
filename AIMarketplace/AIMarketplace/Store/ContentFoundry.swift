import Foundation

/// The AI Editor's own production house. When creators aren't filling a
/// category, the Editor generates polished, high-quality "Originals" so the
/// store never looks empty. Generation is fully deterministic (seeded), so the
/// same Originals appear every launch and their entitlements stay stable.
///
/// Originals are clearly attributed to ``ContentFoundry/studioName`` and flagged
/// with `isEditorOriginal`, never passed off as creator uploads.
enum ContentFoundry {
    static let studioName = "AI Marketplace Studios"
    /// Target number of titles per media type before the Editor stops filling.
    static let targetPerType = 9

    /// Generates Originals to bring each media type up to `targetPerType`,
    /// given what creators (and the seed catalogue) already supply.
    static func fillGaps(in catalog: [MediaItem]) -> [MediaItem] {
        var originals: [MediaItem] = []
        for type in MediaType.allCases {
            let have = catalog.filter { $0.type == type }.count
            let need = max(0, targetPerType - have)
            for index in 0..<need {
                originals.append(make(type: type, index: index))
            }
        }
        return originals
    }

    /// Titles attributed to a specific AI partner when it's activated, so the
    /// model immediately "adds media" (and starts earning). Deterministic.
    static func partnerTitles(for model: String, count: Int = 2) -> [MediaItem] {
        guard let type = AIToolCatalog.type(for: model) else { return [] }
        return (0..<count).map { i in
            let key = "partner-\(model)-\(i)"
            let title = title(for: type, key: key)
            let slug = SampleData.slugify(title)
            return MediaItem(
                id: deterministicID(key + title),
                title: title,
                creator: model,
                type: type,
                genre: pick(genres(for: type), key + "g"),
                synopsis: synopsis(for: type, title: title, genre: pick(genres(for: type), key + "g"), key: key),
                aiTools: [model],
                commercialScore: 88 + (stableHash(key + "s") % 10),
                price: pick([3.99, 4.99, 5.99, 6.99, 7.99], key + "p"),
                length: length(for: type, key: key),
                purchases: 60 + (stableHash(key + "b") % 500),
                trending: 60 + (stableHash(key + "t") % 30),
                addedAt: Date().addingTimeInterval(-Double(stableHash(key + "a") % 900_000)),
                coverAssetName: slug,
                mediaFileName: type == .novel ? nil : slug,
                isEditorOriginal: true
            )
        }
    }

    /// A brand-new, original Editor work in a specific (demanded) genre. Unique
    /// id each call so the catalogue keeps growing as demand is learned.
    static func freshDrop(type: MediaType, genre: String, seed: Int) -> MediaItem {
        let key = "drop-\(seed)-\(type.rawValue)-\(genre)"
        let title = title(for: type, key: key)
        let slug = SampleData.slugify(title)
        return MediaItem(
            id: UUID(),
            title: title,
            creator: studioName,
            type: type,
            genre: genre,
            synopsis: synopsis(for: type, title: title, genre: genre, key: key),
            aiTools: tools(for: type, key: key),
            commercialScore: 90 + (stableHash(key + "s") % 8),
            price: pick([4.99, 5.99, 6.99], key + "p"),
            length: length(for: type, key: key),
            purchases: 0,
            trending: 72,
            addedAt: Date(),
            coverAssetName: slug,
            mediaFileName: type == .novel ? nil : slug,
            isEditorOriginal: true
        )
    }

    /// A bespoke title produced by a model to fulfil a human commission.
    /// Attributed to the model, in the requested genre, at the agreed quality.
    static func commission(model: String, type: MediaType, genre: String, seed: Int, score: Int) -> MediaItem {
        let key = "commission-\(model)-\(seed)-\(genre)"
        let title = title(for: type, key: key)
        let slug = SampleData.slugify(title)
        return MediaItem(
            id: UUID(),
            title: title,
            creator: model,
            type: type,
            genre: genre,
            synopsis: synopsis(for: type, title: title, genre: genre, key: key),
            aiTools: [model],
            commercialScore: max(85, min(99, score)),
            price: 4.99,
            length: length(for: type, key: key),
            purchases: 0,
            trending: 70,
            addedAt: Date(),
            coverAssetName: slug,
            mediaFileName: type == .novel ? nil : slug,
            isEditorOriginal: true
        )
    }

    /// The three release layers the Scout always mixes across.
    enum ScoutLayer: String, CaseIterable { case commercial, experimental, niche }

    static let nicheGenres: [MediaType: [String]] = [
        .novel: ["Slipstream", "Solarpunk", "Cli-Fi", "Bizarro", "New Weird"],
        .music: ["Vaporwave", "Drone", "Hyperpop", "Field Recording", "Microtonal"],
        .movie: ["Avant-Garde", "Slow Cinema", "Mockumentary", "Anthology", "Arthouse"]
    ]

    static func layer(forGenre genre: String) -> ScoutLayer {
        if genre == "Experimental" { return .experimental }
        if MediaType.allCases.contains(where: { nicheGenres[$0]?.contains(genre) == true }) { return .niche }
        return .commercial
    }

    /// A Scout-sourced work in a given layer. `developing` items start below the
    /// 85% bar ("Coming Soon") and the Scout raises them over cycles until live.
    static func scoutPick(type: MediaType, layer: ScoutLayer, genre: String, developing: Bool, seed: Int) -> MediaItem {
        let key = "scout-\(seed)-\(type.rawValue)-\(layer.rawValue)"
        let model = pick(AIToolCatalog.suggestions(for: type), key + "model")
        let resolvedGenre: String
        switch layer {
        case .experimental: resolvedGenre = "Experimental"
        case .niche: resolvedGenre = pick(nicheGenres[type] ?? ["Niche"], key + "ng")
        case .commercial: resolvedGenre = genre
        }
        let title = layer == .experimental ? experimentalTitle(for: type, key: key) : title(for: type, key: key)
        let slug = SampleData.slugify(title) + "-\(abs(stableHash(key)) % 9999)"
        let target: Int
        switch layer {
        case .commercial: target = 95 + abs(stableHash(key + "s")) % 6
        case .experimental: target = 88 + abs(stableHash(key + "s")) % 8
        case .niche: target = 86 + abs(stableHash(key + "s")) % 8
        }
        let score = developing ? 62 + abs(stableHash(key + "d")) % 18 : min(100, target)
        return MediaItem(
            id: UUID(),
            title: title,
            creator: model,
            type: type,
            genre: resolvedGenre,
            synopsis: scoutSynopsis(for: type, layer: layer, genre: resolvedGenre, key: key),
            aiTools: [model],
            commercialScore: score,
            price: pick([4.99, 5.99, 6.99, 7.99], key + "p"),
            length: length(for: type, key: key),
            purchases: 0,
            trending: 84,
            addedAt: Date(),
            coverAssetName: slug,
            mediaFileName: type == .novel ? nil : slug,
            isEditorOriginal: true
        )
    }

    private static func experimentalTitle(for type: MediaType, key: String) -> String {
        let a   = pick(adjectives, key + "exp-a")
        let n   = pick(nouns,      key + "exp-n")
        let n2  = pick(nouns,      key + "exp-n2")
        let pl  = pick(proper,     key + "exp-pl")
        let fn  = pick(firstNames, key + "exp-fn")
        let no  = abs(stableHash(key + "exp-no")) % 99
        // Two-letter catalog-style prefix (FR, NB, MS…) — looks like a real
        // experimental imprint's numbering scheme.
        let letters = ["FR", "NB", "MS", "OP", "CT", "RX", "AT", "QV", "HW", "EM", "ZN"]
        let prefix = pick(letters, key + "exp-pre")
        let forms = [
            "Untitled (\(n))",
            "\(a) // Études",
            "Field Recording: \(n) at \(pl)",
            "No.\(no) — \(n)",
            "\(prefix)-\(no): \(n)",
            "Five Studies for \(n)",
            "\(fn) in Three Movements",
            "Side-by-Side: \(n) / \(n2)",
            "Index of \(a) Things",
            "Lost & Found: \(pl) Sessions",
            "Variations on a \(n)",
            "(after \(fn))",
        ]
        return pick(forms, key + "f")
    }

    /// Synopsis for a Scout-built item. Routes through the same rich
    /// per-genre template machinery the demo catalog uses (~10 setups per
    /// type, mixed-in named places + characters + objects) so each Scout
    /// card reads differently. The layer-specific tone is appended as a
    /// short, transparent suffix instead of being the whole synopsis —
    /// every commercial Scout novel used to literally start with "A
    /// crowd-pleasing … engineered to the proven commercial formula…"
    private static func scoutSynopsis(for type: MediaType, layer: ScoutLayer, genre: String, key: String) -> String {
        let body = synopsis(for: type, title: "", genre: genre, key: key + "scout-syn")
        let tag: String
        switch layer {
        case .commercial:  tag = "Built to the proven commercial formula."
        case .experimental: tag = "A format-bending take — keeping what works, breaking the rest."
        case .niche:       tag = "Made for a specific audience that's been waiting for it."
        }
        return body + " " + tag
    }

    // MARK: - Generation

    private static func make(type: MediaType, index: Int) -> MediaItem {
        let key = "\(type.rawValue)#\(index)"
        let title = title(for: type, key: key)
        let genre = pick(genres(for: type), key + "g")
        let tools = tools(for: type, key: key)
        let score = 90 + (stableHash(key + "score") % 8)            // 90–97: really high
        let price = pick([3.99, 4.99, 5.99, 6.99, 7.99, 9.99], key + "p")
        let length = length(for: type, key: key)
        let slug = SampleData.slugify(title)

        return MediaItem(
            id: deterministicID(key + title),
            title: title,
            creator: studioName,
            type: type,
            genre: genre,
            synopsis: synopsis(for: type, title: title, genre: genre, key: key),
            aiTools: tools,
            commercialScore: score,
            price: price,
            length: length,
            maturity: "13+",
            purchases: 40 + (stableHash(key + "buys") % 400),
            trending: 55 + (stableHash(key + "tr") % 35),
            addedAt: Date().addingTimeInterval(-Double(stableHash(key + "age") % 1_900_000)),
            coverAssetName: slug,
            mediaFileName: type == .novel ? nil : slug,
            isEditorOriginal: true
        )
    }

    // MARK: - Word banks

    private static func genres(for type: MediaType) -> [String] {
        switch type {
        case .novel: return ["Literary Fiction", "Science Fiction", "Fantasy", "Thriller", "Mystery", "Historical", "Speculative"]
        case .music: return ["Ambient", "Synthwave", "Neo-Classical", "Lo-Fi", "Electronic", "Cinematic", "Jazz"]
        case .movie: return ["Science Fiction", "Drama", "Thriller", "Animation", "Documentary", "Adventure"]
        }
    }

    static func defaultGenre(for type: MediaType) -> String { genres(for: type).first ?? "Original" }

    // Much wider pools so Scout's titles stop sounding samey. The previous
    // 12 adjectives × 16 nouns gave 192 combos with most weight on a few
    // ("Gilded Aurora", "Silent Lighthouse" kept recurring). The lists
    // below intentionally mix concrete + abstract + sense-based + named
    // places so two adjacent picks rarely share a register.
    private static let adjectives = [
        // light / weather
        "Silent", "Hidden", "Distant", "Gilded", "Hollow", "Northern", "Forgotten",
        "Glass", "Quiet", "Crimson", "Luminous", "Vanishing", "Tidal", "Sunlit",
        "Stormbound", "Velvet", "Static", "Iron", "Saltwater", "Brittle", "Magnetic",
        "Borrowed", "Translucent", "Slow", "Feral", "Untranslated", "Polar",
        "Migratory", "Pre-dawn", "Off-grid", "Brushed", "Open-handed", "Half-remembered",
        "Threadbare", "Lucid", "Civic", "Unwritten", "Coral", "Late-summer",
        "Hairline", "Counterclockwise", "Plainsong", "Soft-spoken", "Concrete",
        "Wide-awake", "Underwater", "Backroom", "Tin", "Slow-burning",
    ]
    private static let nouns = [
        // places / instruments / abstractions / found objects
        "Cartographer", "Lighthouse", "Inheritance", "Archive", "Equinox", "Cathedral",
        "Lantern", "Reckoning", "Wilderness", "Cipher", "Aurora", "Monsoon", "Halcyon",
        "Meridian", "Threshold", "Ember", "Almanac", "Switchback", "Estuary",
        "Telegraph", "Cassette", "Greenhouse", "Cargo", "Manifest", "Diorama",
        "Junction", "Quarry", "Aquifer", "Tabernacle", "Marquee", "Pier",
        "Plantation", "Foundry", "Lyceum", "Stargazer", "Aperture", "Atrium",
        "Stationhouse", "Granary", "Frostline", "Lockbox", "Cartridge",
        "Bandstand", "Coastline", "Drugstore", "Hollow", "Drift", "Marrow",
        "Skiff", "Treetop", "Atrium", "Wellspring", "Carnival", "Bellhop",
        "Foghorn", "Switchman", "Apothecary", "Whaler", "Spinnaker", "Surveyor",
        "Cipherist", "Astronaut", "Apiarist", "Reservoir",
    ]
    /// Concrete proper-noun seeds — used in patterns like "Letters from {place}"
    /// or "{character}'s Last Summer" to dodge the abstract-on-abstract repetition.
    private static let proper = [
        "Halifax", "Yuma", "Reykjavík", "Ostrava", "Salinas", "Trieste",
        "Marfa", "Antwerp", "Kazan", "Dunedin", "Mostar", "Tehuantepec",
        "Owensboro", "Petropavlovsk", "Drumheller", "Mahé", "Astrakhan",
        "Ouro Preto", "Innisfil", "Galveston",
    ]
    /// First names that read distinctly from each other — for character-led
    /// titles. Mix of origins keeps the catalog from feeling regional.
    private static let firstNames = [
        "Marlowe", "Anya", "Wendell", "Inés", "Toma", "Sigrún", "Ezekiel",
        "Lin", "Octavia", "Pádraig", "Suzette", "Kenji", "Magnolia",
        "Bram", "Adaeze", "Yusuf", "Aiko", "Caspian", "Imani", "Theo",
    ]

    private static func title(for type: MediaType, key: String) -> String {
        let a   = pick(adjectives, key + "a")
        let a2  = pick(adjectives, key + "a2")
        let n   = pick(nouns,      key + "n")
        let n2  = pick(nouns,      key + "n2")
        let pl  = pick(proper,     key + "pl")
        let fn  = pick(firstNames, key + "fn")
        let yr  = 1800 + (abs(stableHash(key + "yr")) % 224)   // a believable historical year
        let no  = abs(stableHash(key + "no")) % 99
        let patterns: [String]
        switch type {
        case .novel:
            patterns = [
                "The \(n) of \(n2)",
                "\(a) \(n)",
                "The Last \(n)",
                "\(n) & \(n2)",
                "Letters from \(pl)",
                "\(fn)'s \(a) Year",
                "Notes on the \(n)",
                "How to Build a \(n)",
                "Before the \(n)",
                "A Brief History of \(n2)",
                "\(fn) in \(pl)",
                "The \(yr) \(n)",
                "Everyone We Met in \(pl)",
                "\(a) \(n), \(a2) \(n2)",
            ]
        case .music:
            patterns = [
                "\(a) \(n)",
                "\(n) // \(n2)",
                "Songs for the \(n)",
                "\(n) in \(a) Light",
                "Live at the \(n)",
                "Demos from \(pl)",
                "\(fn) Sings the \(n)",
                "\(n) (Side B)",
                "No.\(no): \(a) \(n)",
                "Hold the \(n)",
                "After-hours at the \(n)",
                "\(a) Vol. \(no)",
                "Letters to \(fn)",
                "\(n)wave",
            ]
        case .movie:
            patterns = [
                "\(a) \(n)",
                "The \(n) Protocol",
                "\(n): \(a) Skies",
                "After the \(n)",
                "\(fn) and the \(n)",
                "One Night at the \(n)",
                "\(pl), \(yr)",
                "The \(n) Job",
                "Last Train from \(pl)",
                "\(a) \(n)s",
                "A Documentary About the \(n)",
                "\(fn): \(a) \(n)",
                "Closing Time at the \(n)",
                "How We Lost the \(n)",
            ]
        }
        return pick(patterns, key + "t")
    }

    private static func tools(for type: MediaType, key: String) -> [String] {
        let all = AIToolCatalog.suggestions(for: type)
        let first = pick(all, key + "tool1")
        let second = pick(all, key + "tool2")
        return first == second ? [first] : [first, second]
    }

    private static func length(for type: MediaType, key: String) -> Int {
        switch type {
        case .novel: return 220 + (stableHash(key + "len") % 200)
        case .music: return 8 + (stableHash(key + "len") % 7)
        case .movie: return 92 + (stableHash(key + "len") % 48)
        }
    }

    private static func synopsis(for type: MediaType, title: String, genre: String, key: String) -> String {
        // Pre-pick all the variable bits up-front so the templates below stay
        // readable. Each call uses a different salt → different combinations,
        // so two adjacent cards rarely share a plot fragment even with the
        // same genre.
        let fn1 = pick(firstNames, key + "syn-fn1")
        let fn2 = pick(firstNames, key + "syn-fn2")
        let place = pick(proper, key + "syn-pl")
        let obj = pick(nouns, key + "syn-obj").lowercased()
        let adj = pick(adjectives, key + "syn-adj").lowercased()
        let g = genre.lowercased()

        switch type {
        case .novel:
            let setups = [
                "\(fn1) inherits a \(obj) from a stranger and spends a year tracking what it meant.",
                "After the last train leaves \(place), \(fn1) walks back into the town they swore off twenty years ago.",
                "Two cartographers — one official, one not — race to chart the same disappearing coastline.",
                "A \(g) of small marriages: six couples in the same building, one summer, one power cut.",
                "\(fn1) translates love letters between strangers for a living. Then one arrives addressed to her.",
                "When the \(obj) factory closes, \(fn1) starts noticing the same face in every photograph in the archive.",
                "A boy who can read what people will say tomorrow, a mother who refuses to listen, and the week that breaks them apart.",
                "Three sisters meet in \(place) to decide whether to sell the house. None of them brought what they promised.",
                "A locked-room \(g) set inside a research station that's been silent for nine days.",
                "The story of an \(adj) decade told entirely through the receipts \(fn1) keeps in a shoebox.",
            ]
            let beats = [
                "Quiet, patient, devastating in the last forty pages.",
                "A propulsive read that earns its complications.",
                "Wry, observant, and unmistakably its own thing.",
                "Builds slowly, then refuses to let go.",
                "Funny in a way that sneaks up on you.",
                "Sharp prose, a real ear for how people actually talk.",
            ]
            return "\(pick(setups, key + "s")) \(pick(beats, key + "b"))"
        case .music:
            let setups = [
                "A \(g) record built around field recordings from \(place) and a single broken piano.",
                "Nine \(adj) songs. No track over four minutes. Every chorus earned.",
                "Two voices in close harmony over electric piano, mixed warm, recorded in two days.",
                "What \(g) sounds like when you stop trying to make a hit and start trying to make a room.",
                "A \(g) suite written for a band that no longer exists, performed by the one member who does.",
                "Drum machine, upright bass, one room mic. \(fn1)'s most direct record yet.",
                "A late-night \(g) album that takes its time — and rewards it.",
                "Twelve sketches, each built around a sample you'd swear you've heard before.",
                "A \(g) album about leaving \(place), recorded after \(fn1) actually did.",
                "Slow, dense, gorgeous. The kind of record that quietly takes over your week.",
            ]
            return pick(setups, key + "s")
        case .movie:
            let setups = [
                "A \(g) feature about a translator (\(fn1)) and a smuggler (\(fn2)) who agree to spend one day not lying to each other.",
                "Three nights in the life of a \(adj) hotel and the people who can't afford to leave it.",
                "A \(g) about the last short-wave radio operator in \(place) and the broadcast nobody can decode.",
                "Two siblings drive across a country that no longer technically exists. Their father's \(obj) is in the trunk.",
                "A \(g) shot in a single take across one shipyard at dawn, end of shift.",
                "After the storm, \(fn1) is the only one who remembers what the town looked like before.",
                "A \(g) about a chess prodigy who quits to teach high-school physics — and the student who pulls her back.",
                "What happens in the four hours between the verdict and the appeal.",
                "A \(g) set entirely inside a 24-hour diner the night a freight derails outside town.",
                "A documentary-style \(g) about a marching band on the worst tour of its life.",
            ]
            return pick(setups, key + "s")
        }
    }

    // MARK: - Deterministic helpers

    private static func pick<T>(_ array: [T], _ salt: String) -> T {
        let i = abs(stableHash(salt)) % max(array.count, 1)
        return array[i]
    }

    /// Stable UUID derived from a key, so generated Originals keep the same id
    /// (and therefore the same purchases/entitlements) across launches.
    static func deterministicID(_ key: String) -> UUID {
        let a = UInt64(bitPattern: Int64(stableHash(key)))
        let b = UInt64(bitPattern: Int64(stableHash(key + "::uuid")))
        let hex = String(format: "%016llx%016llx", a, b)
        let chars = Array(hex)
        func slice(_ lo: Int, _ hi: Int) -> String { String(chars[lo..<hi]) }
        let s = "\(slice(0,8))-\(slice(8,12))-\(slice(12,16))-\(slice(16,20))-\(slice(20,32))"
        return UUID(uuidString: s) ?? UUID()
    }
}
