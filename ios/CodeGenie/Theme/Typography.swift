import SwiftUI

extension Font {
    static let displayLarge = Font.system(size: 44, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 32, weight: .bold, design: .rounded)
    static let titleSerif = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let monoSmall = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let monoMedium = Font.system(size: 16, weight: .medium, design: .monospaced)
}

extension Text {
    /// Gradient title used on hero sections — keeps the text legible against
    /// glass surfaces while still feeling premium.
    func auroraStyle() -> some View {
        self.foregroundStyle(LiquidGlass.auroraGradient)
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
    }
}
