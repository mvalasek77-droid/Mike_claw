import SwiftUI

/// A production revision pass. Studios track changes by colored drafts
/// (White → Blue → Pink → Yellow → Green …); each new pass stamps changed
/// pages with its color so the crew shooting from paper knows what moved.
struct Revision: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String          // "Blue Revision"
    var colorName: String     // "Blue"
    var date: Date
    var note: String
    var locked: Bool          // locked pages keep their numbering

    init(id: UUID = UUID(),
         name: String,
         colorName: String,
         date: Date = .now,
         note: String = "",
         locked: Bool = false) {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.date = date
        self.note = note
        self.locked = locked
    }
}

enum RevisionPalette {
    /// Standard WGA production revision order.
    static let order = ["White", "Blue", "Pink", "Yellow", "Green",
                        "Goldenrod", "Buff", "Salmon", "Cherry"]

    static func color(for name: String) -> Color {
        switch name {
        case "Blue": return Color(red: 0.45, green: 0.62, blue: 0.95)
        case "Pink": return Color(red: 0.96, green: 0.62, blue: 0.78)
        case "Yellow": return Color(red: 0.96, green: 0.86, blue: 0.40)
        case "Green": return Palette.success
        case "Goldenrod": return Color(red: 0.85, green: 0.65, blue: 0.13)
        case "Buff": return Color(red: 0.94, green: 0.87, blue: 0.69)
        case "Salmon": return Color(red: 0.98, green: 0.50, blue: 0.45)
        case "Cherry": return Palette.danger
        default: return .secondary
        }
    }

    static func next(after name: String?) -> String {
        guard let name, let idx = order.firstIndex(of: name), idx + 1 < order.count else {
            return order.first ?? "White"
        }
        return order[idx + 1]
    }
}
