import CoreGraphics

/// The original cast of WATCHFIGHTER: ASCENDANT. All characters, names, and
/// lore are original to this project — the genre *mechanics* are cloned, the
/// *content* is not.
extension CharacterSpec {

    /// Rushdown — fast, electric, relentless pressure.
    static let volt = CharacterSpec(
        id: "volt",
        name: "VOLT",
        title: "The Live Wire",
        bio: "A street-circuit racer rebuilt with arc-reactor limbs. Fights to "
           + "outrun the corporation that wired her.",
        maxHealth: 100, walkSpeed: 2.6,
        special: Move.special(damage: 16, reach: 58, pushback: 18, startup: 5),
        exSpecial: Move.ex(from: Move.special(damage: 16, reach: 58, pushback: 18, startup: 5)),
        homeStageID: "neon_strip",
        bodyColor: RGBA(0.20, 0.72, 1.0), accentColor: RGBA(0.85, 0.95, 1.0)
    )

    /// Grappler / zoner — armored, slow, devastating up close.
    static let bastion = CharacterSpec(
        id: "bastion",
        name: "BASTION",
        title: "The Standing Wall",
        bio: "A demolition golem awakened beneath a fallen city. Believes the "
           + "tournament will decide who rebuilds the world.",
        maxHealth: 124, walkSpeed: 1.6,
        special: Move.special(damage: 20, reach: 40, pushback: 26, startup: 8, launches: true),
        exSpecial: Move.ex(from: Move.special(damage: 20, reach: 40, pushback: 26, startup: 8, launches: true)),
        homeStageID: "ruins",
        bodyColor: RGBA(0.62, 0.55, 0.45), accentColor: RGBA(1.0, 0.7, 0.2),
        // Slow but crushing — Bastion's heavy hits like a wrecking ball.
        heavy: Move(kind: .heavy, startup: 12, active: 3, recovery: 18,
                    damage: 19, chip: 4, hitstun: 22, blockstun: 14,
                    pushback: 18, reach: 34, meterGain: 12, cancelable: true)
    )

    /// Fire zoner — keeps distance with projectiles.
    static let ember = CharacterSpec(
        id: "ember",
        name: "EMBER",
        title: "The Last Cinder",
        bio: "A volcano-shrine guardian. Each match feeds the eternal flame she "
           + "is sworn to keep alive.",
        maxHealth: 96, walkSpeed: 2.1,
        special: Move.projectile(damage: 14, speed: 7, startup: 8),
        exSpecial: Move.ex(from: Move.projectile(damage: 14, speed: 7, startup: 8)),
        homeStageID: "caldera",
        bodyColor: RGBA(1.0, 0.42, 0.18), accentColor: RGBA(1.0, 0.85, 0.3)
    )

    /// Ice control — slow projectile, big freezing reward.
    static let frost = CharacterSpec(
        id: "frost",
        name: "FROST",
        title: "The Quiet Winter",
        bio: "An exiled cryomancer searching for the rival who shattered her "
           + "clan. Speaks only in the cold.",
        maxHealth: 100, walkSpeed: 1.9,
        special: Move.projectile(damage: 12, speed: 5, startup: 10),
        exSpecial: Move.ex(from: Move.projectile(damage: 12, speed: 5, startup: 10)),
        homeStageID: "glacier",
        bodyColor: RGBA(0.55, 0.85, 0.95), accentColor: RGBA(0.95, 0.98, 1.0)
    )

    /// Teleport rushdown — high-risk mixups.
    static let mirage = CharacterSpec(
        id: "mirage",
        name: "MIRAGE",
        title: "The Borrowed Face",
        bio: "A masked phantom who steps between seconds. No one agrees on what "
           + "Mirage actually wants — least of all Mirage.",
        maxHealth: 92, walkSpeed: 2.8,
        special: Move.special(damage: 15, reach: 70, pushback: 14, startup: 4),
        exSpecial: Move.ex(from: Move.special(damage: 15, reach: 70, pushback: 14, startup: 4)),
        homeStageID: "temple",
        bodyColor: RGBA(0.55, 0.35, 0.85), accentColor: RGBA(0.85, 0.7, 1.0)
    )

    /// All-rounder ("shoto" archetype) — the player's default, balanced.
    static let tetsu = CharacterSpec(
        id: "tetsu",
        name: "TETSU",
        title: "The Open Palm",
        bio: "A wandering martial artist chasing the meaning of a master's last "
           + "lesson. Enters every tournament to test the answer.",
        maxHealth: 108, walkSpeed: 2.2,
        special: Move.special(damage: 17, reach: 46, pushback: 16, startup: 6, launches: true),
        exSpecial: Move.ex(from: Move.special(damage: 17, reach: 46, pushback: 16, startup: 6, launches: true)),
        homeStageID: "dojo",
        bodyColor: RGBA(0.9, 0.9, 0.92), accentColor: RGBA(0.85, 0.2, 0.2)
    )

    /// Final boss — overtuned, the tournament's host.
    static let onyx = CharacterSpec(
        id: "onyx",
        name: "ONYX",
        title: "The Ascendant",
        bio: "The one who built the tournament and never lost it. Wears every "
           + "champion's last move as a trophy.",
        maxHealth: 150, walkSpeed: 2.4,
        special: Move.special(damage: 24, reach: 64, pushback: 24, startup: 5, launches: true),
        exSpecial: Move.ex(from: Move.special(damage: 24, reach: 64, pushback: 24, startup: 5, launches: true)),
        homeStageID: "throne",
        bodyColor: RGBA(0.12, 0.12, 0.16), accentColor: RGBA(0.8, 0.1, 0.5)
    )

    /// Swashbuckling duelist (original pirate archetype) — long cutlass reach,
    /// unpredictable drunken footwork. Not based on any real actor or character.
    static let corsair = CharacterSpec(
        id: "corsair",
        name: "CORSAIR",
        title: "The Tipsy Tide",
        bio: "A grinning sea-rogue who climbs the tower for the one treasure the "
           + "ocean never gave up. Fights loose, lands hard.",
        maxHealth: 100, walkSpeed: 2.3,
        special: Move.special(damage: 16, reach: 78, pushback: 16, startup: 6),
        exSpecial: Move.ex(from: Move.special(damage: 16, reach: 78, pushback: 16, startup: 6)),
        homeStageID: "ship",
        bodyColor: RGBA(0.30, 0.22, 0.16), accentColor: RGBA(0.95, 0.8, 0.25)
    )

    /// Armored bounty hunter (original sci-fi archetype) — blaster zoning.
    static let nova = CharacterSpec(
        id: "nova",
        name: "NOVA",
        title: "The Last Contract",
        bio: "A helmeted gun-for-hire tracking a bounty that climbed the tower "
           + "and never came down. Keeps the lane honest with plasma.",
        maxHealth: 98, walkSpeed: 2.2,
        special: Move.projectile(damage: 15, speed: 8, startup: 7),
        exSpecial: Move.ex(from: Move.projectile(damage: 15, speed: 8, startup: 7)),
        homeStageID: "spaceport",
        bodyColor: RGBA(0.35, 0.38, 0.42), accentColor: RGBA(1.0, 0.55, 0.1)
    )

    /// FINAL BOSS — an undefeated heavyweight boxer with bold geometric face
    /// markings (an original design). His haymaker is ARMORED and devastating:
    /// it plows through pokes, so the only safe answer is a clean parry. Brutal
    /// but fair — not literally unbeatable, just the hardest wall in the tower.
    /// Original character; not based on any real boxer's name, face, or likeness.
    static let titus = CharacterSpec(
        id: "titus",
        name: "TITUS",
        title: "The Undefeated",
        bio: "No one has heard him speak and no one has heard a bell save him. "
           + "The tower's last door is a square of canvas and two fists.",
        maxHealth: 180, walkSpeed: 2.5,
        special: Move.special(damage: 30, reach: 52, pushback: 30, startup: 6,
                              launches: true, armor: true),
        exSpecial: Move.ex(from: Move.special(damage: 30, reach: 52, pushback: 30,
                                              startup: 6, launches: true, armor: true)),
        homeStageID: "ring",
        bodyColor: RGBA(0.36, 0.22, 0.14), accentColor: RGBA(0.95, 0.95, 1.0),
        guardedByRitual: true            // INVINCIBLE until the ritual is performed
    )

    /// Swordmaster (original katana archetype) — longest melee reach, a drawing
    /// cut that launches. Original character; not based on any actor or film role.
    static let vesper = CharacterSpec(
        id: "vesper",
        name: "VESPER",
        title: "The Drawn Blade",
        bio: "A wandering swordmaster who answers the tower's bell to test one "
           + "thing: a single, perfect cut.",
        maxHealth: 94, walkSpeed: 2.4,
        special: Move.special(damage: 18, reach: 84, pushback: 16, startup: 7, launches: true),
        exSpecial: Move.ex(from: Move.special(damage: 18, reach: 84, pushback: 16, startup: 7, launches: true)),
        homeStageID: "garden",
        bodyColor: RGBA(0.55, 0.10, 0.18), accentColor: RGBA(0.88, 0.90, 0.96),
        // The blade gives Vesper the longest normals in the cast.
        light: Move(kind: .light, startup: 4, active: 2, recovery: 7,
                    damage: 6, chip: 1, hitstun: 12, blockstun: 8,
                    pushback: 6, reach: 34, meterGain: 6, cancelable: true),
        heavy: Move(kind: .heavy, startup: 10, active: 3, recovery: 17,
                    damage: 14, chip: 3, hitstun: 20, blockstun: 12,
                    pushback: 14, reach: 42, meterGain: 10, cancelable: true),
        // A long downward air slash to match the reach of her ground blade.
        airHeavy: Move(kind: .heavy, startup: 6, active: 4, recovery: 8,
                       damage: 13, chip: 3, hitstun: 18, blockstun: 10,
                       pushback: 10, reach: 38, meterGain: 9, loY: -26, hiY: 40)
    )

    /// Acrobatic athlete (original lifeguard/swimmer archetype) — fast, mobile,
    /// strong aerials. Original character; not based on any real person.
    static let marina = CharacterSpec(
        id: "marina",
        name: "MARINA",
        title: "The Riptide",
        bio: "A champion open-water rescue swimmer who fights like the sea — "
           + "fast, relentless, impossible to hold down.",
        maxHealth: 100, walkSpeed: 2.8,
        special: Move.special(damage: 15, reach: 50, pushback: 20, startup: 5),
        exSpecial: Move.ex(from: Move.special(damage: 15, reach: 50, pushback: 20, startup: 5)),
        homeStageID: "pier",
        bodyColor: RGBA(0.95, 0.55, 0.35), accentColor: RGBA(0.2, 0.7, 0.9),
        light: Move(kind: .light, startup: 2, active: 2, recovery: 5,
                    damage: 5, chip: 1, hitstun: 12, blockstun: 8,
                    pushback: 5, reach: 24, meterGain: 6, cancelable: true),
        // The strongest aerials on the roster — a long, lingering dive kick.
        airHeavy: Move(kind: .heavy, startup: 5, active: 6, recovery: 8,
                       damage: 14, chip: 3, hitstun: 18, blockstun: 10,
                       pushback: 10, reach: 32, meterGain: 9, loY: -30, hiY: 42)
    )

    /// SECRET unlockable (12 wins) — an original martial-arts-cinema legend who
    /// never left the soundstage and provides his own sound effects. Lightning
    /// kicks, glass cannon, maximum ham. Not based on any real actor or film.
    static let feng = CharacterSpec(
        id: "feng",
        name: "FENG",
        title: "The Last Reel",
        bio: "A washed-up B-movie kung-fu star who wandered into the tower looking "
           + "for craft services and never found the exit. Still in character. Always.",
        maxHealth: 94, walkSpeed: 2.9,
        special: Move.special(damage: 16, reach: 62, pushback: 14, startup: 4, launches: true),
        exSpecial: Move.ex(from: Move.special(damage: 16, reach: 62, pushback: 14, startup: 4, launches: true)),
        homeStageID: "soundstage",
        bodyColor: RGBA(0.86, 0.70, 0.20), accentColor: RGBA(1.0, 0.95, 0.7),
        light: Move(kind: .light, startup: 2, active: 2, recovery: 6,
                    damage: 6, chip: 1, hitstun: 12, blockstun: 8,
                    pushback: 6, reach: 28, meterGain: 7, cancelable: true)
    )

    /// Glamour zoner (original "supermodel" archetype) — blinding flash bulbs
    /// for zoning, glass cannon. Original character; no real-person likeness.
    static let sable = CharacterSpec(
        id: "sable",
        name: "SABLE",
        title: "The Runway",
        bio: "She heard the tower had the best lighting in the world. It does. She "
           + "is not leaving until everyone agrees, ideally while unconscious.",
        maxHealth: 92, walkSpeed: 2.6,
        special: Move.projectile(damage: 14, speed: 8, startup: 7),
        exSpecial: Move.ex(from: Move.projectile(damage: 14, speed: 8, startup: 7)),
        homeStageID: "runway",
        bodyColor: RGBA(0.95, 0.25, 0.55), accentColor: RGBA(1.0, 0.9, 0.4)
    )

    /// Showman dancer (original stage-performer archetype) — rhythmic mixups and
    /// strong aerials. Original character; not based on any performer or routine.
    static let groove = CharacterSpec(
        id: "groove",
        name: "GROOVE",
        title: "The Showstopper",
        bio: "Forty years on a stage that no longer exists. The tower gave him a "
           + "new audience: everyone he beats has to clap.",
        maxHealth: 98, walkSpeed: 2.8,
        special: Move.special(damage: 16, reach: 56, pushback: 16, startup: 5, launches: true),
        exSpecial: Move.ex(from: Move.special(damage: 16, reach: 56, pushback: 16, startup: 5, launches: true)),
        homeStageID: "soundstage",
        bodyColor: RGBA(0.15, 0.15, 0.18), accentColor: RGBA(0.95, 0.85, 0.3)
    )

    /// MC / poet-warrior (original hip-hop archetype) — charismatic, balanced,
    /// strong mid-range. Original character; no real-person likeness, no lyrics.
    static let verse = CharacterSpec(
        id: "verse",
        name: "VERSE",
        title: "The Cypher",
        bio: "Came up to the tower to drop the realest bars in history and found "
           + "out the only critics left were fists. He adapted. Loudly.",
        maxHealth: 104, walkSpeed: 2.3,
        special: Move.special(damage: 17, reach: 50, pushback: 18, startup: 6, launches: true),
        exSpecial: Move.ex(from: Move.special(damage: 17, reach: 50, pushback: 18, startup: 6, launches: true)),
        homeStageID: "plaza",
        bodyColor: RGBA(0.25, 0.35, 0.55), accentColor: RGBA(0.95, 0.8, 0.2)
    )

    /// Selectable cast (bosses excluded; later entries are win-gated unlocks).
    static let selectable: [CharacterSpec] =
        [tetsu, volt, ember, frost, mirage, bastion, corsair, nova, vesper, marina,
         sable, feng, groove, verse]

    /// The arcade-ladder order the player climbs — ends with the boss, TITUS.
    static let arcadeLadder: [CharacterSpec] =
        [volt, ember, frost, corsair, mirage, nova, bastion, onyx, titus]

    static func byID(_ id: String) -> CharacterSpec {
        (selectable + [onyx, titus]).first { $0.id == id } ?? tetsu
    }

    /// A bit of personality: the winner's one-liner. All original, all silly.
    var winQuote: String {
        switch id {
        case "tetsu":   return "The lesson continues. You were the homework."
        case "volt":    return "Blink and you'll miss the rematch. ...You blinked."
        case "ember":   return "You're toast. Literally. I double-checked."
        case "frost":   return "Cool down. ...That was the whole joke, yes."
        case "mirage":  return "Did I win? Did you? Even I lost track, honestly."
        case "bastion": return "I am not stuck. You were simply in the way. Were."
        case "corsair": return "No hard feelings! The rum has feelings. Not me."
        case "nova":    return "Bounty collected. Tip jar's by the airlock."
        case "vesper":  return "One cut. You blinked at the second out of politeness."
        case "marina":  return "Out of your depth. Get it? Because I swim. Anyway."
        case "onyx":    return "The tower thanks you for donating your dignity."
        case "titus":   return "(He cracks his knuckles. That is the entire speech.)"
        case "feng":    return "And… CUT! Print it, that's the take. Somebody fetch my smoothie."
        case "sable":   return "The judges are unanimous. You're a two. Out of a possible me."
        case "groove":  return "Tip your waitstaff. They watched you lose."
        case "verse":   return "Round's over. The mic stays warm."
        default:        return "GG."
        }
    }

    /// Pre-round trash talk, shown on the VS card for flavor.
    var taunt: String {
        switch id {
        case "tetsu":   return "Show me what your master forgot to teach you."
        case "volt":    return "I already won. The light just hasn't reached you yet."
        case "ember":   return "Stop, drop, and lose."
        case "frost":   return "...this won't take long. It never does."
        case "mirage":  return "Pick the real me. Wrong answer hurts."
        case "bastion": return "Brace yourself. Or don't. Same result."
        case "corsair": return "Best two falls out of a barrel of rum?"
        case "nova":    return "Nothing personal. Mostly nothing."
        case "vesper":  return "Draw your weapon. I only need one swing for both of us."
        case "marina":  return "Hope you stretched. I didn't."
        case "onyx":    return "Climbers fall. It's in the name of the job."
        case "titus":   return "(silence, and two raised fists)"
        case "feng":    return "HYAAA! …sorry, that's contractual. Okay — HYAAA!"
        case "sable":   return "Try not to fall in love. Or just… fall."
        case "groove":  return "Two left feet? I'll only need one."
        case "verse":   return "Bring a notebook. This is a lesson."
        default:        return "Let's go."
        }
    }

    /// Skin tone for the procedural human look (golems/cyborgs get fitting tones).
    var skin: RGBA {
        switch id {
        case "bastion": return RGBA(0.55, 0.50, 0.42)   // stone golem
        case "onyx":    return RGBA(0.22, 0.20, 0.24)    // obsidian
        case "titus":   return RGBA(0.42, 0.28, 0.20)
        case "volt":    return RGBA(0.83, 0.66, 0.55)
        case "ember":   return RGBA(0.80, 0.55, 0.42)
        case "frost":   return RGBA(0.85, 0.80, 0.78)
        case "mirage":  return RGBA(0.62, 0.50, 0.46)
        case "nova":    return RGBA(0.70, 0.55, 0.45)
        case "vesper":  return RGBA(0.80, 0.66, 0.56)
        case "marina":  return RGBA(0.78, 0.58, 0.46)
        case "corsair": return RGBA(0.72, 0.54, 0.42)
        case "feng":    return RGBA(0.82, 0.64, 0.50)
        case "sable":   return RGBA(0.55, 0.40, 0.32)
        case "groove":  return RGBA(0.48, 0.34, 0.26)
        case "verse":   return RGBA(0.50, 0.36, 0.28)
        default:        return RGBA(0.80, 0.62, 0.50)    // tetsu + fallback
        }
    }

    /// Sex/figure read for proportions (broad shoulders vs. narrower frame).
    var feminine: Bool {
        ["volt", "ember", "frost", "marina", "sable", "vesper", "nova"].contains(id)
    }

    var hairStyle: HairStyle {
        switch id {
        case "bastion", "onyx", "titus": return .bald
        case "vesper", "marina", "sable", "ember", "frost", "mirage": return .long
        default: return .short
        }
    }

    /// Distinct hair colours (not tied to the accent) for variety/ethnicity.
    var hairColor: RGBA {
        switch id {
        case "volt":    return RGBA(0.85, 0.90, 1.0)   // electric white-blue
        case "ember":   return RGBA(0.85, 0.30, 0.12)  // fiery
        case "frost":   return RGBA(0.90, 0.92, 0.98)  // platinum
        case "mirage":  return RGBA(0.45, 0.30, 0.65)  // violet
        case "marina":  return RGBA(0.62, 0.45, 0.22)  // sun-bleached
        case "sable":   return RGBA(0.08, 0.06, 0.07)  // jet black
        case "vesper":  return RGBA(0.10, 0.09, 0.11)  // black
        case "corsair": return RGBA(0.20, 0.12, 0.07)  // dark brown
        case "nova":    return RGBA(0.22, 0.15, 0.10)
        case "feng":    return RGBA(0.10, 0.09, 0.10)
        case "groove":  return RGBA(0.20, 0.20, 0.22)  // greying
        case "verse":   return RGBA(0.09, 0.08, 0.09)
        default:        return RGBA(0.14, 0.10, 0.08)   // tetsu + fallback (dark brown)
        }
    }

    /// Procedural identity (the SF2 "readable silhouette" idea, done originally).
    var hasWeapon: Bool { id == "vesper" || id == "corsair" }
    var weaponColor: RGBA { id == "vesper" ? RGBA(0.88, 0.90, 0.97) : RGBA(0.72, 0.62, 0.32) }
    var bigGloves: Bool { id == "titus" }

    /// Body type for the procedural renderer's proportions.
    var build: Build {
        switch id {
        case "bastion", "titus", "onyx": return .heavy      // broad bruisers
        case "ember", "frost", "mirage", "vesper", "marina", "sable": return .lithe
        default: return .athletic
        }
    }

    /// Battle chatter — what they shout when they land a combo.
    var hype: String {
        switch id {
        case "tetsu":   return "Felt that?"
        case "volt":    return "Too slow!"
        case "ember":   return "Well done!"
        case "frost":   return "Stay down. Stay cold."
        case "mirage":  return "Which hit was real?"
        case "bastion": return "STAND. ASIDE."
        case "corsair": return "Hah! Another round!"
        case "nova":    return "Locked on."
        case "vesper":  return "One cut. One."
        case "marina":  return "Wipeout!"
        case "onyx":    return "Climb DOWN."
        case "titus":   return "(thud. thud. thud.)"
        case "feng":    return "HWA-TAH! Did you get that on film?!"
        case "sable":   return "Strike a pose. On the floor."
        case "groove":  return "And a-one, and a-TWO!"
        case "verse":   return "That's the hook. Literally."
        default:        return "Hah!"
        }
    }

    /// What they yelp when they take a big hit.
    var hurt: String {
        switch id {
        case "tetsu":   return "Tch—!"
        case "volt":    return "Short circuit!"
        case "ember":   return "Snuffed?!"
        case "frost":   return "...cold."
        case "mirage":  return "Rude."
        case "bastion": return "A crack. One crack."
        case "corsair": return "Me rum!!"
        case "nova":    return "Contract's getting personal."
        case "vesper":  return "A scratch."
        case "marina":  return "Riptide pulls back!"
        case "onyx":    return "Impossible…"
        case "titus":   return "(he barely blinks)"
        case "feng":    return "That's NOT in the script!"
        case "sable":   return "Not the face! The brand!"
        case "groove":  return "Off-beat! OFF-BEAT!"
        case "verse":   return "Aight, no more freestyle."
        default:        return "Ngh!"
        }
    }

    /// Flavor name for this character's special, shown in the movelist.
    var specialName: String {
        switch id {
        case "tetsu":   return "Rising Palm"
        case "volt":    return "Arc Dash"
        case "ember":   return "Cinderbolt"
        case "frost":   return "Glacier Spike"
        case "mirage":  return "Phase Strike"
        case "bastion": return "Quake Slam"
        case "corsair": return "Cutlass Rush"
        case "nova":    return "Plasma Shot"
        case "vesper":  return "Drawing Cut"
        case "marina":  return "Riptide"
        case "onyx":    return "Ascendant Crush"
        case "titus":   return "Haymaker"
        case "feng":    return "Flying Reel Kick"
        case "sable":   return "Flashbulb"
        case "groove":  return "Showstopper Spin"
        case "verse":   return "Mic Drop"
        default:        return "Special"
        }
    }
}
