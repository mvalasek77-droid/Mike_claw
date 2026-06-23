import SwiftUI

/// App-wide preferences that aren't tied to a single project.
@MainActor
final class AppState: ObservableObject {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    @AppStorage("appearance") private var appearanceRaw: String = Appearance.system.rawValue
    @AppStorage("reduceHaptics") var reduceHaptics: Bool = false

    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue; objectWillChange.send() }
    }

    var colorScheme: ColorScheme? { appearance.colorScheme }
}
