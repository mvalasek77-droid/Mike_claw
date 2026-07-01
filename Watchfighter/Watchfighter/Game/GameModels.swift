import CoreGraphics
import Foundation

enum FighterPhase: Equatable {
    case running
    case gameOver
}

enum FighterSide: Equatable {
    case player
    case opponent
}

enum FighterAction: Equatable {
    case idle
    case walk
    case crouch
    case blocking
    case jab
    case kick
    case jumpKick
    case throwAttack
    case special
    case projectile
    case hit
    case victory
    case defeated
}

enum StrikeKind: Equatable {
    case hit
    case blocked
    case special
    case projectile
    case throwImpact
    case blood
    case round
    case finisher
    case headPop
    case bodyBurst
    case armDrop
    case vampireBite
}

enum CombatStyle: Equatable {
    case balanced
    case rushdown
    case grappler
    case zoner
    case acrobat
    case bruiser
    case titan

    func damageMultiplier(for action: FighterAction) -> CGFloat {
        switch (self, action) {
        case (.rushdown, .jab), (.rushdown, .kick):
            return 1.10
        case (.rushdown, .projectile):
            return 0.88
        case (.grappler, .throwAttack):
            return 1.38
        case (.grappler, .projectile):
            return 0.72
        case (.zoner, .projectile):
            return 1.26
        case (.zoner, .throwAttack), (.zoner, .kick):
            return 0.88
        case (.acrobat, .jumpKick):
            return 1.28
        case (.acrobat, .throwAttack):
            return 0.82
        case (.bruiser, .kick), (.bruiser, .throwAttack), (.bruiser, .special):
            return 1.14
        case (.bruiser, .jab):
            return 0.94
        case (.titan, _):
            return 1.16
        default:
            return 1.0
        }
    }

    func rangeMultiplier(for action: FighterAction) -> CGFloat {
        switch (self, action) {
        case (.rushdown, .jab), (.rushdown, .kick):
            return 1.05
        case (.grappler, .throwAttack):
            return 1.28
        case (.grappler, .projectile):
            return 0.76
        case (.zoner, .projectile):
            return 1.20
        case (.zoner, .throwAttack):
            return 0.82
        case (.acrobat, .jumpKick):
            return 1.18
        case (.bruiser, .throwAttack), (.bruiser, .kick):
            return 1.08
        case (.titan, .jab), (.titan, .kick), (.titan, .throwAttack):
            return 1.12
        default:
            return 1.0
        }
    }

    func cooldownMultiplier(for action: FighterAction) -> TimeInterval {
        switch (self, action) {
        case (.rushdown, .jab), (.rushdown, .kick):
            return 0.86
        case (.acrobat, .jumpKick), (.acrobat, .kick):
            return 0.88
        case (.grappler, .throwAttack):
            return 0.88
        case (.grappler, .projectile):
            return 1.22
        case (.zoner, .projectile):
            return 0.88
        case (.bruiser, _):
            return 1.08
        case (.titan, _):
            return 1.12
        default:
            return 1.0
        }
    }

    var meterBuildRate: CGFloat {
        switch self {
        case .rushdown, .acrobat:
            return 1.14
        case .zoner:
            return 1.08
        case .grappler:
            return 0.94
        case .bruiser:
            return 0.98
        case .titan:
            return 0.82
        case .balanced:
            return 1.0
        }
    }

    var guardPressure: CGFloat {
        switch self {
        case .bruiser, .grappler:
            return 1.18
        case .zoner:
            return 1.08
        case .rushdown, .acrobat:
            return 0.96
        case .titan:
            return 1.28
        case .balanced:
            return 1.0
        }
    }

    var throwPush: CGFloat {
        switch self {
        case .grappler:
            return 0.13
        case .bruiser, .titan:
            return 0.10
        case .acrobat, .zoner:
            return 0.06
        case .balanced, .rushdown:
            return 0.08
        }
    }
}

enum StoryChapter: Int, CaseIterable, Equatable {
    case cinderGate = 1
    case neonRooftop
    case stormBridge
    case pirateCove
    case dragonAlley
    case sunPier
    case runwayTerminal
    case blackoutBase
    case launchFoundry
    case goldRally
    case icePalace
    case redCarpet
    case cageNight
    case obsidianThrone
    case millionRoom

    static func chapter(for round: Int) -> StoryChapter {
        Self(rawValue: min(max(round, 1), Self.allCases.count)) ?? .cinderGate
    }

    var title: String {
        switch self {
        case .cinderGate:
            return "CINDER GATE"
        case .neonRooftop:
            return "NEON ROOFTOP"
        case .stormBridge:
            return "STORM BRIDGE"
        case .pirateCove:
            return "PIRATE COVE"
        case .dragonAlley:
            return "DRAGON ALLEY"
        case .sunPier:
            return "SUN PIER"
        case .runwayTerminal:
            return "RUNWAY TERMINAL"
        case .blackoutBase:
            return "BLACKOUT BASE"
        case .launchFoundry:
            return "LAUNCH FOUNDRY"
        case .goldRally:
            return "GOLD RALLY"
        case .icePalace:
            return "ICE PALACE"
        case .redCarpet:
            return "RED CARPET"
        case .cageNight:
            return "CAGE NIGHT"
        case .obsidianThrone:
            return "OBSIDIAN THRONE"
        case .millionRoom:
            return "MILLION ROOM"
        }
    }

    var subtitle: String {
        switch self {
        case .cinderGate:
            return "First blood in the temple yard."
        case .neonRooftop:
            return "No retreat above the city."
        case .stormBridge:
            return "Strike through the thunder line."
        case .pirateCove:
            return "Board the cursed casino ship."
        case .dragonAlley:
            return "Fast hands under red lanterns."
        case .sunPier:
            return "Lifeguards, neon, and bad choices."
        case .runwayTerminal:
            return "High fashion, higher kicks."
        case .blackoutBase:
            return "No cameras. No backup."
        case .launchFoundry:
            return "Rocket money meets street justice."
        case .goldRally:
            return "Big mouth, bigger haymaker."
        case .icePalace:
            return "A cold grip on the old empire."
        case .redCarpet:
            return "Flashbulbs hide a blade dance."
        case .cageNight:
            return "Five rounds compressed into one."
        case .obsidianThrone:
            return "The war king guards the elevator."
        case .millionRoom:
            return "Only the million-shot counter works."
        }
    }

    var arenaTag: String {
        switch self {
        case .cinderGate:
            return "GATE"
        case .neonRooftop:
            return "ROOF"
        case .stormBridge:
            return "STORM"
        case .pirateCove:
            return "COVE"
        case .dragonAlley:
            return "DRAGON"
        case .sunPier:
            return "PIER"
        case .runwayTerminal:
            return "RUNWAY"
        case .blackoutBase:
            return "BASE"
        case .launchFoundry:
            return "LAUNCH"
        case .goldRally:
            return "GOLD"
        case .icePalace:
            return "ICE"
        case .redCarpet:
            return "STAR"
        case .cageNight:
            return "CAGE"
        case .obsidianThrone:
            return "THRONE"
        case .millionRoom:
            return "MILLION"
        }
    }
}

enum FighterArchetype: CaseIterable, Equatable {
    case kael
    case nyra
    case rook
    case voss
    case mara
    case lennox
    case sunny
    case nova
    case specter
    case cosmo
    case brass
    case volkov
    case zara
    case cage
    case kairo
    case titan
    /// Secret vampire — unlocked in VS mode only after a full tournament clear.
    /// Not part of `versusRoster`/the ladder; GameScreen appends him once earned.
    case dracula
    /// The Hell demon met in the Pit after a ladder fall (`WatchfighterState.pitActive`).
    /// Not part of `versusRoster`/the ladder; the engine spawns him directly.
    case abaddon

    static var versusRoster: [FighterArchetype] {
        [
            .nyra,
            .rook,
            .voss,
            .mara,
            .lennox,
            .sunny,
            .nova,
            .specter,
            .cosmo,
            .brass,
            .volkov,
            .zara,
            .cage,
            .kairo,
            .titan
        ]
    }

    var displayName: String {
        switch self {
        case .kael:
            return "KAEL"
        case .nyra:
            return "NYRA"
        case .rook:
            return "ROOK"
        case .voss:
            return "VOSS"
        case .mara:
            return "MARA"
        case .lennox:
            return "LENNOX"
        case .sunny:
            return "SUNNY"
        case .nova:
            return "NOVA"
        case .specter:
            return "SPECTER"
        case .cosmo:
            return "COSMO"
        case .brass:
            return "BRASS"
        case .volkov:
            return "VOLKOV"
        case .zara:
            return "ZARA"
        case .cage:
            return "CAGE"
        case .kairo:
            return "KAIRO"
        case .titan:
            return "TITUS"
        case .dracula:
            return "DRACULA"
        case .abaddon:
            return "ABADDON"
        }
    }

    var subtitle: String {
        switch self {
        case .kael:
            return "Iron Dragon"
        case .nyra:
            return "Velvet Viper"
        case .rook:
            return "Chrome Bruiser"
        case .voss:
            return "Storm Raider"
        case .mara:
            return "Cutlass Captain"
        case .lennox:
            return "Dragon Fist"
        case .sunny:
            return "Rescue Siren"
        case .nova:
            return "Runway Phantom"
        case .specter:
            return "Shadow Ops"
        case .cosmo:
            return "Rocket Baron"
        case .brass:
            return "Golden Brawler"
        case .volkov:
            return "Ice Regent"
        case .zara:
            return "Starlit Mirage"
        case .cage:
            return "Octagon Crusher"
        case .kairo:
            return "War King"
        case .titan:
            return "Iron Comet Boxer"
        case .dracula:
            return "The Undying Count"
        case .abaddon:
            return "The Pit's Own Fork"
        }
    }

    var imageName: String {
        switch self {
        case .kael:
            return "DigitizedHero"
        case .nyra:
            return "DigitizedAce"
        case .rook:
            return "DigitizedDrone"
        case .voss:
            return "DigitizedRaider"
        case .mara, .lennox, .sunny, .nova, .specter, .cosmo, .brass, .volkov, .zara, .cage, .titan, .dracula, .abaddon:
            return ""
        case .kairo:
            return "DigitizedWarlord"
        }
    }

    var usesBitmapSprite: Bool {
        !imageName.isEmpty
    }

    var aspectRatio: CGFloat {
        switch self {
        case .kael:
            return 388.0 / 617.0
        case .nyra:
            return 345.0 / 638.0
        case .rook:
            return 385.0 / 640.0
        case .voss:
            return 465.0 / 603.0
        case .mara:
            return 0.56
        case .lennox:
            return 0.52
        case .sunny:
            return 0.54
        case .nova:
            return 0.50
        case .specter:
            return 0.58
        case .cosmo:
            return 0.62
        case .brass:
            return 0.64
        case .volkov:
            return 0.58
        case .zara:
            return 0.52
        case .cage:
            return 0.62
        case .kairo:
            return 428.0 / 640.0
        case .titan:
            return 0.66
        case .dracula:
            return 0.54
        case .abaddon:
            return 0.68
        }
    }

    var heightFactor: CGFloat {
        switch self {
        case .kael:
            return 0.48
        case .nyra:
            return 0.49
        case .rook:
            return 0.49
        case .voss:
            return 0.50
        case .mara, .lennox, .sunny, .nova, .specter, .cosmo, .brass, .volkov, .zara, .cage:
            return 0.50
        case .kairo:
            return 0.54
        case .titan:
            return 0.90
        case .dracula:
            return 0.52
        case .abaddon:
            return 0.74
        }
    }

    var footOffset: CGFloat {
        switch self {
        case .kairo, .titan:
            return 0.40
        default:
            return 0.39
        }
    }

    var maxHealth: Int {
        switch self {
        case .kael:
            return 100
        case .nyra:
            return 92
        case .rook:
            return 108
        case .voss:
            return 112
        case .mara:
            return 96
        case .lennox:
            return 94
        case .sunny:
            return 98
        case .nova:
            return 94
        case .specter:
            return 110
        case .cosmo:
            return 104
        case .brass:
            return 118
        case .volkov:
            return 116
        case .zara:
            return 96
        case .cage:
            return 120
        case .kairo:
            return 122
        case .titan:
            return 360
        case .dracula:
            return 132
        case .abaddon:
            return 150
        }
    }

    var power: CGFloat {
        switch self {
        case .kael:
            return 1.0
        case .nyra:
            return 0.94
        case .rook:
            return 1.08
        case .voss:
            return 1.10
        case .mara:
            return 1.02
        case .lennox:
            return 1.05
        case .sunny:
            return 0.98
        case .nova:
            return 0.96
        case .specter:
            return 1.12
        case .cosmo:
            return 1.04
        case .brass:
            return 1.16
        case .volkov:
            return 1.14
        case .zara:
            return 0.99
        case .cage:
            return 1.20
        case .kairo:
            return 1.18
        case .titan:
            return 1.78
        case .dracula:
            return 1.24
        case .abaddon:
            return 1.42
        }
    }

    var quickness: CGFloat {
        switch self {
        case .nyra:
            return 1.14
        case .voss:
            return 0.92
        case .mara:
            return 1.10
        case .lennox:
            return 1.24
        case .sunny:
            return 1.08
        case .nova:
            return 1.20
        case .specter:
            return 1.02
        case .cosmo:
            return 0.98
        case .brass:
            return 0.88
        case .volkov:
            return 0.90
        case .zara:
            return 1.18
        case .cage:
            return 1.04
        case .kairo:
            return 0.82
        case .titan:
            return 0.88
        case .dracula:
            return 1.32
        case .abaddon:
            return 0.94
        default:
            return 1.0
        }
    }

    var combatStyle: CombatStyle {
        switch self {
        case .kael, .mara, .sunny, .zara:
            return .balanced
        case .nyra, .lennox, .specter:
            return .rushdown
        case .nova, .voss, .dracula:
            return .acrobat
        case .cosmo, .rook:
            return .zoner
        case .cage, .volkov:
            return .grappler
        case .brass, .kairo, .abaddon:
            return .bruiser
        case .titan:
            return .titan
        }
    }

    var signatureMove: String {
        switch self {
        case .kael:
            return "IRON DRAGON"
        case .nyra:
            return "VIPER KISS"
        case .rook:
            return "CHROME RUSH"
        case .voss:
            return "STORM HOOK"
        case .mara:
            return "CUTLASS FEINT"
        case .lennox:
            return "DRAGON SNAP"
        case .sunny:
            return "PIER RESCUE"
        case .nova:
            return "RUNWAY RAZOR"
        case .specter:
            return "BLACKOUT BREACH"
        case .cosmo:
            return "ORBITAL CHECK"
        case .brass:
            return "GOLDEN TANTRUM"
        case .volkov:
            return "COLD CLINCH"
        case .zara:
            return "FLASH STEP"
        case .cage:
            return "OCTAGON GRIND"
        case .kairo:
            return "WAR KING"
        case .titan:
            return "MILLION SHOT"
        case .dracula:
            return "CRIMSON BITE"
        case .abaddon:
            return "BRIMSTONE FORK"
        }
    }

    var techniqueName: String {
        switch self {
        case .kael:
            return "Iron Dragon Chain"
        case .nyra:
            return "Serpent Rush"
        case .rook:
            return "Chrome Pulse"
        case .voss:
            return "Cyclone Leap"
        case .mara:
            return "Cutlass Clinch"
        case .lennox:
            return "Dragon Snap"
        case .sunny:
            return "Red Rescue Kick"
        case .nova:
            return "Runway Mirage"
        case .specter:
            return "Blackout Breach"
        case .cosmo:
            return "Orbital Zoning"
        case .brass:
            return "Golden Haymaker"
        case .volkov:
            return "Ice Lock"
        case .zara:
            return "Flash Step"
        case .cage:
            return "Cage Grinder"
        case .kairo:
            return "War Hammer"
        case .titan:
            return "Titus Peekaboom"
        case .dracula:
            return "Crimson Bite"
        case .abaddon:
            return "Brimstone Fork"
        }
    }

    var techniqueSummary: String {
        switch self {
        case .kael:
            return "Balanced dragon boxing: jab, step, kick, repeat until meter burns."
        case .nyra:
            return "Fast viper pressure: short hops, knife-hand jabs, sudden low guard."
        case .rook:
            return "Chrome zoning: retreats behind pulse shots, then checks the rush."
        case .voss:
            return "Storm acrobatics: jump kicks from weird angles and quick exits."
        case .mara:
            return "Pirate close-work: hook, clinch, and a cutlass feint at the wrist."
        case .lennox:
            return "Dragon-fist rushdown: three fast body shots into a snapping kick."
        case .sunny:
            return "Red one-piece rescue style: lifeguard sprint, knee lift, pier kick."
        case .nova:
            return "Runway feints: glides backward, then lands a heel-blade jump kick."
        case .specter:
            return "Shadow breach: blocks the first swing and answers with compact elbows."
        case .cosmo:
            return "Rocket baron zoning: orbital shots force you into his launch lane."
        case .brass:
            return "Golden brawler tantrum: slow guard crush into a huge right hand."
        case .volkov:
            return "Ice-lock grappling: waits, clinches, and drains your guard."
        case .zara:
            return "Flash-step glamour: slips outside and stabs back with quick kicks."
        case .cage:
            return "Cage grinder: pressure walk, throw chain, shoulder crush."
        case .kairo:
            return "War hammer: heavy armored strikes with brutal guard pressure."
        case .titan:
            return "Titus is a giant original boxer. Only an 8-hit chain plus full-meter special can drop him."
        case .dracula:
            return "Erratic aerial vampire: floats out of range, then snaps in for a bite that turns its target."
        case .abaddon:
            return "Pit demon: hurls brimstone fire at range, then closes for a heavy pitchfork stab."
        }
    }

    var storyBlurb: String {
        switch self {
        case .kael:
            return "Kael enters the ladder to break the broadcast syndicate that digitized every arena."
        case .nyra:
            return "Nyra guards the first gate and smiles like she already poisoned the bell."
        case .rook:
            return "Rook was built for riot control, then learned prize money was faster."
        case .voss:
            return "Voss fights on bridges during storms because clean air slows him down."
        case .mara:
            return "Mara captains a casino ship where every debt is settled at knuckle range."
        case .lennox:
            return "Lennox studied old dragon forms and removed every move that looked polite."
        case .sunny:
            return "Sunny turned a beach rescue drill into a red-hot pier-fighting circuit."
        case .nova:
            return "Nova treats the runway like a duel lane and every flashbulb like a timer."
        case .specter:
            return "Specter deletes cameras, exits, and then anyone still standing."
        case .cosmo:
            return "Cosmo bought a rocket foundry and hired fighters to test the launch alarms."
        case .brass:
            return "Brass performs for crowds, gold lights, and anyone dumb enough to boo."
        case .volkov:
            return "Volkov rules an ice palace where a handshake is already a submission."
        case .zara:
            return "Zara learned red-carpet footwork from cameras that never saw the blade."
        case .cage:
            return "Cage compresses five rounds of pressure into one watch-sized nightmare."
        case .kairo:
            return "Kairo waits by the throne elevator, heavy as a siege engine."
        case .titan:
            return "Titus is not a legend or a lookalike. He is a three-story final boxer built to end runs."
        case .dracula:
            return "Dracula only wakes for a champion who already beat the tower once — and never for a fair fight."
        case .abaddon:
            return "Abaddon doesn't climb the tower. He waits in the Pit for whoever falls out of it."
        }
    }

    var finisherKind: StrikeKind {
        switch self {
        case .nyra, .mara, .zara, .dracula:
            return .headPop
        case .rook, .cosmo, .brass, .kairo, .titan, .abaddon:
            return .bodyBurst
        default:
            return .armDrop
        }
    }

    var finisherTitle: String {
        switch finisherKind {
        case .headPop:
            return "HEAD POP"
        case .bodyBurst:
            return "BODY BURST"
        case .armDrop:
            return "ARM RIP"
        default:
            return "FINISH"
        }
    }

    func preferredAttack(distance: CGFloat, pressure: CGFloat, meter: CGFloat) -> FighterAction? {
        if meter >= 1, distance < 0.62 {
            switch combatStyle {
            case .zoner, .titan:
                return .projectile
            case .bruiser:
                return .special
            default:
                break
            }
        }

        switch self {
        case .nyra, .lennox:
            return distance < 0.34 ? (pressure > 0.44 ? .kick : .jab) : nil
        case .rook, .cosmo:
            return distance < 0.66 ? .projectile : nil
        case .voss, .nova, .zara:
            return distance < 0.38 ? .jumpKick : nil
        case .mara, .volkov, .cage:
            return distance < 0.24 ? .throwAttack : (distance < 0.34 ? .kick : nil)
        case .sunny:
            return distance < 0.36 ? (pressure > 0.58 ? .jumpKick : .kick) : nil
        case .specter:
            return distance < 0.31 ? (pressure > 0.52 ? .jab : .blocking) : nil
        case .brass, .kairo:
            return distance < 0.32 ? (pressure > 0.48 ? .kick : .jab) : nil
        case .titan:
            return distance < 0.40 ? (pressure > 0.52 ? .special : .jab) : nil
        case .dracula:
            // Erratic: darts in for the bite (throw) at close range, otherwise
            // flourishes a jump kick to stay unpredictable and airborne.
            return distance < 0.32 ? (pressure > 0.42 ? .throwAttack : .jumpKick) : nil
        case .abaddon:
            // Brimstone at range, pitchfork (kick/throw) once he closes in.
            if distance < 0.62, pressure > 0.50 { return .projectile }
            return distance < 0.30 ? .throwAttack : (distance < 0.40 ? .kick : nil)
        default:
            return distance < 0.30 ? .jab : nil
        }
    }

    var isMillionBoss: Bool {
        self == .titan
    }

    /// Dracula's bite marks the defender as a vampire on a successful, landed
    /// throw — see `WatchfighterEngine.performAttack`.
    var inflictsVampireBite: Bool {
        self == .dracula
    }
}

struct GameInput: Equatable {
    var targetX: CGFloat
    var attacking: Bool
    var special: Bool
    var dashStrike: Bool
    var jump: Bool
    var crouching: Bool
    var throwing: Bool
    var blocking: Bool

    init(
        targetX: CGFloat = 0.25,
        attacking: Bool = false,
        special: Bool = false,
        dashStrike: Bool = false,
        jump: Bool = false,
        crouching: Bool = false,
        throwing: Bool = false,
        blocking: Bool = false
    ) {
        self.targetX = targetX
        self.attacking = attacking
        self.special = special
        self.dashStrike = dashStrike
        self.jump = jump
        self.crouching = crouching
        self.throwing = throwing
        self.blocking = blocking
    }
}

struct DuelFighter: Equatable {
    var archetype: FighterArchetype
    var x: CGFloat
    var y: CGFloat = 0.78
    var health: Int
    var maxHealth: Int
    var meter: CGFloat
    var guardMeter: CGFloat
    var action: FighterAction
    var actionTimer: TimeInterval
    var actionDuration: TimeInterval = 0   // full length of current action, for smooth animation
    var hitStun: TimeInterval
    var combo: Int
    var facing: CGFloat
    /// Set once bitten by Dracula: darker skin, bat wings, and an airborne
    /// stance for the rest of the fight (WatchfighterCanvas renders the look).
    var isVampire: Bool = false

    init(archetype: FighterArchetype, x: CGFloat, facing: CGFloat) {
        self.archetype = archetype
        self.x = x
        self.health = archetype.maxHealth
        self.maxHealth = archetype.maxHealth
        self.meter = 0.24
        self.guardMeter = 1
        self.action = .idle
        self.actionTimer = 0
        self.actionDuration = 0
        self.hitStun = 0
        self.combo = 0
        self.facing = facing
        self.isVampire = false
    }
}

struct FighterStrike: Identifiable, Equatable {
    let id: Int
    var side: FighterSide
    var x: CGFloat
    var y: CGFloat
    var age: TimeInterval
    var lifetime: TimeInterval
    var kind: StrikeKind
}

struct WatchfighterState: Equatable {
    var phase: FighterPhase = .running
    var score = 0
    var round = 1
    var roundTimer: TimeInterval = 60
    var playerWins = 0
    var opponentWins = 0
    var chapter: StoryChapter = .cinderGate
    var combo = 0
    var maxCombo = 0
    var comboClock: TimeInterval = 0
    var bannerText = "ROUND 1"
    var bannerDetail = StoryChapter.cinderGate.subtitle
    var bannerTimer: TimeInterval = 2.2
    var finisherText = ""
    var finisherTimer: TimeInterval = 0
    var player = DuelFighter(archetype: .kael, x: 0.25, facing: 1)
    var opponent = DuelFighter(archetype: .nyra, x: 0.75, facing: -1)
    var strikes: [FighterStrike] = []
    var elapsed: TimeInterval = 0
    var winnerText = ""
    /// Currently fighting Abaddon in the Pit after a ladder fall — see
    /// `WatchfighterEngine.resolveRoundIfNeeded`/`startNextRound`.
    var pitActive: Bool = false
}
