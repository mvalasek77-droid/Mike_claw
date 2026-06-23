import SwiftUI

extension Font {
    static let displayLarge = Font.system(size: 40, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 30, weight: .bold, design: .rounded)
    static let titleSerif = Font.system(size: 22, weight: .semibold, design: .serif)

    /// Courier-family monospace is the lingua franca of screenwriting; the
    /// editor renders the page in it so what writers see maps to printed pages.
    static func screenplay(_ size: CGFloat = 17) -> Font {
        .custom("Courier", size: size)
    }

    static let labelSmall = Font.system(size: 12, weight: .semibold, design: .rounded)
}

extension Text {
    func marqueeStyle() -> some View {
        self.foregroundStyle(Palette.marqueeGradient)
            .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
    }
}
