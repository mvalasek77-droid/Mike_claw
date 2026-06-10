import CoreGraphics

/// Silhouette theme that drives how `StageBuilder` draws parallax layers.
enum StageMotif: Equatable {
    case city        // neon skyline
    case ruins       // broken pillars
    case volcano     // jagged peaks + lava glow
    case glacier     // ice spires
    case temple      // pagoda silhouettes
    case dojo        // beams + paper screens
    case throne      // monolithic obsidian hall
    case ship        // mast + sail (pirate)
    case ring        // ropes + corner posts (boxing arena)
}

/// A fighting-game stage, described purely as colors + a motif so the engine
/// has no SpriteKit dependency. `StageBuilder` turns this into nodes.
struct StageSpec: Equatable {
    let id: String
    let name: String
    let skyTop: RGBA
    let skyBottom: RGBA
    let farColor: RGBA      // distant silhouette layer
    let midColor: RGBA      // mid silhouette layer
    let groundColor: RGBA
    let accent: RGBA        // glow / lights
    let motif: StageMotif
}

enum StageLibrary {
    static let all: [StageSpec] = [
        StageSpec(id: "neon_strip", name: "NEON STRIP",
                  skyTop: RGBA(0.05, 0.02, 0.12), skyBottom: RGBA(0.35, 0.08, 0.32),
                  farColor: RGBA(0.10, 0.06, 0.22), midColor: RGBA(0.16, 0.10, 0.34),
                  groundColor: RGBA(0.06, 0.04, 0.10), accent: RGBA(0.3, 0.9, 1.0),
                  motif: .city),
        StageSpec(id: "ruins", name: "FALLEN CITY",
                  skyTop: RGBA(0.18, 0.16, 0.22), skyBottom: RGBA(0.55, 0.42, 0.40),
                  farColor: RGBA(0.22, 0.20, 0.26), midColor: RGBA(0.30, 0.27, 0.30),
                  groundColor: RGBA(0.14, 0.12, 0.13), accent: RGBA(1.0, 0.7, 0.3),
                  motif: .ruins),
        StageSpec(id: "caldera", name: "ASH CALDERA",
                  skyTop: RGBA(0.12, 0.03, 0.02), skyBottom: RGBA(0.6, 0.18, 0.05),
                  farColor: RGBA(0.20, 0.05, 0.03), midColor: RGBA(0.32, 0.08, 0.04),
                  groundColor: RGBA(0.10, 0.03, 0.02), accent: RGBA(1.0, 0.55, 0.15),
                  motif: .volcano),
        StageSpec(id: "glacier", name: "STILL GLACIER",
                  skyTop: RGBA(0.06, 0.12, 0.22), skyBottom: RGBA(0.45, 0.62, 0.78),
                  farColor: RGBA(0.20, 0.34, 0.46), midColor: RGBA(0.32, 0.50, 0.62),
                  groundColor: RGBA(0.16, 0.26, 0.34), accent: RGBA(0.8, 0.95, 1.0),
                  motif: .glacier),
        StageSpec(id: "temple", name: "MIDNIGHT TEMPLE",
                  skyTop: RGBA(0.06, 0.04, 0.14), skyBottom: RGBA(0.24, 0.16, 0.42),
                  farColor: RGBA(0.12, 0.08, 0.24), midColor: RGBA(0.20, 0.13, 0.36),
                  groundColor: RGBA(0.08, 0.05, 0.14), accent: RGBA(0.7, 0.55, 1.0),
                  motif: .temple),
        StageSpec(id: "dojo", name: "DAWN DOJO",
                  skyTop: RGBA(0.25, 0.16, 0.20), skyBottom: RGBA(0.85, 0.55, 0.42),
                  farColor: RGBA(0.30, 0.20, 0.22), midColor: RGBA(0.42, 0.28, 0.26),
                  groundColor: RGBA(0.22, 0.14, 0.12), accent: RGBA(1.0, 0.8, 0.5),
                  motif: .dojo),
        StageSpec(id: "throne", name: "THE SUMMIT",
                  skyTop: RGBA(0.02, 0.0, 0.04), skyBottom: RGBA(0.20, 0.02, 0.16),
                  farColor: RGBA(0.06, 0.02, 0.10), midColor: RGBA(0.12, 0.03, 0.16),
                  groundColor: RGBA(0.04, 0.01, 0.06), accent: RGBA(0.9, 0.1, 0.55),
                  motif: .throne),
        StageSpec(id: "ship", name: "ROGUE TIDE",
                  skyTop: RGBA(0.04, 0.06, 0.16), skyBottom: RGBA(0.45, 0.40, 0.30),
                  farColor: RGBA(0.10, 0.12, 0.22), midColor: RGBA(0.16, 0.14, 0.18),
                  groundColor: RGBA(0.16, 0.10, 0.06), accent: RGBA(0.95, 0.8, 0.3),
                  motif: .ship),
        StageSpec(id: "spaceport", name: "ORBIT NINE",
                  skyTop: RGBA(0.02, 0.02, 0.08), skyBottom: RGBA(0.10, 0.06, 0.22),
                  farColor: RGBA(0.08, 0.10, 0.20), midColor: RGBA(0.14, 0.16, 0.28),
                  groundColor: RGBA(0.05, 0.06, 0.10), accent: RGBA(1.0, 0.5, 0.1),
                  motif: .city),
        StageSpec(id: "ring", name: "THE LAST BELL",
                  skyTop: RGBA(0.02, 0.02, 0.03), skyBottom: RGBA(0.20, 0.05, 0.05),
                  farColor: RGBA(0.10, 0.08, 0.08), midColor: RGBA(0.18, 0.10, 0.10),
                  groundColor: RGBA(0.22, 0.18, 0.16), accent: RGBA(1.0, 0.85, 0.4),
                  motif: .ring),
        StageSpec(id: "garden", name: "BLADE GARDEN",
                  skyTop: RGBA(0.10, 0.04, 0.10), skyBottom: RGBA(0.55, 0.25, 0.30),
                  farColor: RGBA(0.16, 0.08, 0.16), midColor: RGBA(0.26, 0.12, 0.22),
                  groundColor: RGBA(0.10, 0.06, 0.10), accent: RGBA(1.0, 0.6, 0.7),
                  motif: .temple),
        StageSpec(id: "pier", name: "SUNSET PIER",
                  skyTop: RGBA(0.10, 0.10, 0.28), skyBottom: RGBA(0.95, 0.55, 0.35),
                  farColor: RGBA(0.20, 0.16, 0.30), midColor: RGBA(0.30, 0.20, 0.30),
                  groundColor: RGBA(0.18, 0.12, 0.14), accent: RGBA(0.3, 0.8, 0.95),
                  motif: .ship),
        StageSpec(id: "soundstage", name: "STAGE 7",
                  skyTop: RGBA(0.03, 0.03, 0.04), skyBottom: RGBA(0.14, 0.12, 0.08),
                  farColor: RGBA(0.10, 0.09, 0.06), midColor: RGBA(0.18, 0.15, 0.08),
                  groundColor: RGBA(0.10, 0.09, 0.07), accent: RGBA(1.0, 0.85, 0.3),
                  motif: .dojo),
        StageSpec(id: "runway", name: "THE RUNWAY",
                  skyTop: RGBA(0.10, 0.02, 0.10), skyBottom: RGBA(0.55, 0.12, 0.35),
                  farColor: RGBA(0.18, 0.05, 0.16), midColor: RGBA(0.30, 0.08, 0.24),
                  groundColor: RGBA(0.12, 0.04, 0.10), accent: RGBA(1.0, 0.85, 0.4),
                  motif: .city),
        StageSpec(id: "plaza", name: "MIDNIGHT PLAZA",
                  skyTop: RGBA(0.03, 0.04, 0.10), skyBottom: RGBA(0.10, 0.14, 0.26),
                  farColor: RGBA(0.08, 0.10, 0.18), midColor: RGBA(0.14, 0.18, 0.28),
                  groundColor: RGBA(0.07, 0.08, 0.12), accent: RGBA(0.4, 0.85, 1.0),
                  motif: .city),
    ]

    static func stage(id: String) -> StageSpec {
        all.first { $0.id == id } ?? all[0]
    }
}
