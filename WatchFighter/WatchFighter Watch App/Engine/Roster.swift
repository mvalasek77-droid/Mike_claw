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

    /// Selectable cast (boss excluded from select screen).
    static let selectable: [CharacterSpec] = [tetsu, volt, ember, frost, mirage, bastion]

    /// The arcade-ladder order the player climbs in story mode.
    static let arcadeLadder: [CharacterSpec] = [volt, ember, frost, mirage, bastion, onyx]

    static func byID(_ id: String) -> CharacterSpec {
        (selectable + [onyx]).first { $0.id == id } ?? tetsu
    }
}
