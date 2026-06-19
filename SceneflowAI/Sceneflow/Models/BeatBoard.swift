import SwiftUI

/// A single index card on the beat board — the digital equivalent of pinning
/// note cards to a corkboard while breaking a story.
struct Beat: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var summary: String
    /// Which structural act/column this card lives in.
    var act: Int
    /// Stable ordering within an act.
    var order: Int
    var colorTag: BeatColor
    /// Optional link to a scene heading element id, so a card can jump to its
    /// scene in the editor.
    var linkedSceneID: UUID?

    init(id: UUID = UUID(),
         title: String,
         summary: String = "",
         act: Int = 1,
         order: Int = 0,
         colorTag: BeatColor = .neutral,
         linkedSceneID: UUID? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.act = act
        self.order = order
        self.colorTag = colorTag
        self.linkedSceneID = linkedSceneID
    }
}

enum BeatColor: String, Codable, CaseIterable, Identifiable {
    case neutral, amber, blue, green, red, purple
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .neutral: return .gray
        case .amber: return Palette.accent
        case .blue: return Palette.ink
        case .green: return Palette.success
        case .red: return Palette.danger
        case .purple: return Color(red: 0.71, green: 0.41, blue: 1.0)
        }
    }
}

/// One act column on the board. Three-act is the default; templates can
/// install more columns (see StructureTemplate).
struct ActColumn: Identifiable, Hashable {
    var number: Int
    var name: String
    var id: Int { number }
}
