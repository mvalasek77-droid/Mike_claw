import SwiftUI

/// Centralised colour, gradient and geometry tokens for AI Marketplace.
///
/// The browse/consumption side leans cinematic-dark (Netflix / Apple TV),
/// while the publishing side borrows Amazon KDP's warm "ink + amber" palette.
/// Both share the same neutral foundation so the app reads as one product.
enum Theme {
    // Cinematic accent (consumption side)
    static let accent = Color(red: 0.90, green: 0.12, blue: 0.20)
    static let accentSoft = Color(red: 1.00, green: 0.33, blue: 0.38)

    // KDP / publishing accent (creation side)
    static let kdp = Color(red: 0.96, green: 0.62, blue: 0.12)
    static let kdpDeep = Color(red: 0.83, green: 0.45, blue: 0.05)

    static let gold = Color(red: 1.00, green: 0.80, blue: 0.30)
    static let success = Color(red: 0.27, green: 0.83, blue: 0.52)
    static let warning = Color(red: 1.00, green: 0.66, blue: 0.20)
    static let danger = Color(red: 0.97, green: 0.28, blue: 0.31)

    // Neutrals
    static let bg = Color(red: 0.035, green: 0.035, blue: 0.05)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.13)
    static let surfaceHigh = Color(red: 0.15, green: 0.15, blue: 0.19)
    static let ink = Color.white
    static let inkSoft = Color.white.opacity(0.66)
    static let inkFaint = Color.white.opacity(0.40)
    static let hairline = Color.white.opacity(0.12)

    static let cornerL: CGFloat = 22
    static let cornerM: CGFloat = 14
    static let cornerS: CGFloat = 9

    static let brandGradient = LinearGradient(
        colors: [accent, Color(red: 0.62, green: 0.10, blue: 0.42)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let kdpGradient = LinearGradient(
        colors: [kdp, kdpDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Full-bleed cinematic background used behind the consumption surfaces.
struct AppBackground: View {
    var glow: Color = Theme.accent
    var body: some View {
        ZStack {
            Theme.bg
            LinearGradient(
                colors: [glow.opacity(0.22), .clear],
                startPoint: .top,
                endPoint: .center
            )
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.45)],
                center: .center,
                startRadius: 240,
                endRadius: 760
            )
        }
        .ignoresSafeArea()
    }
}

extension Font {
    static let displayXL = Font.system(size: 40, weight: .heavy, design: .rounded)
    static let displayL = Font.system(size: 30, weight: .bold, design: .rounded)
    static let titleRounded = Font.system(size: 22, weight: .bold, design: .rounded)
}

extension View {
    /// Standard horizontal page padding.
    func screenPadding() -> some View { self.padding(.horizontal, 18) }
}
