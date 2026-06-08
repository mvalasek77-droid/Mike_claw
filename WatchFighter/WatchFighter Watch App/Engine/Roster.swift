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
        bodyColor: RGBA(0.62, 0.55, 0.45), accentColor: RGBA(1.0, 0.7, 0.2)
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
        bodyColor: RGBA(0.55, 0.10, 0.18), accentColor: RGBA(0.88, 0.90, 0.96)
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
        bodyColor: RGBA(0.95, 0.55, 0.35), accentColor: RGBA(0.2, 0.7, 0.9)
    )

    /// Selectable cast (bosses excluded from the select screen).
    static let selectable: [CharacterSpec] =
        [tetsu, volt, ember, frost, mirage, bastion, corsair, nova, vesper, marina]

    /// The arcade-ladder order the player climbs — ends with the boss, TITUS.
    static let arcadeLadder: [CharacterSpec] =
        [volt, ember, frost, corsair, mirage, nova, bastion, onyx, titus]

    static func byID(_ id: String) -> CharacterSpec {
        (selectable + [onyx, titus]).first { $0.id == id } ?? tetsu
    }
}
