import SwiftUI

/// Centralised colour, gradient and geometry tokens for AI Marketplace.
///
/// The browse/consumption side leans cinematic-dark (Netflix / Apple TV),
/// while the publishing side borrows Amazon KDP's warm "ink + amber" palette.
/// Both share the same neutral foundation so the app reads as one product.
enum Theme {
    // Cinematic accent (consumption side) — lime green
    static let accent = Color(red: 0.42, green: 0.86, blue: 0.20)
    static let accentSoft = Color(red: 0.62, green: 0.95, blue: 0.40)

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
        colors: [accent, Color(red: 0.09, green: 0.52, blue: 0.34)],
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

    /// Applies Apple's iOS 26 Liquid Glass material when the SDK/runtime
    /// supports it, and is a no-op everywhere else so the app builds and runs
    /// coherently on iOS 17–25.
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = Theme.cornerL) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Subtle depth: a two-layer cast shadow (tight contact + soft ambient) plus
    /// a top-light highlight stroke. Used on raised glass surfaces to give the
    /// fluid-glass parallax feel.
    func depth(_ corner: CGFloat = Theme.cornerL, strong: Bool = false) -> some View {
        self
            .shadow(color: .black.opacity(strong ? 0.35 : 0.22), radius: strong ? 8 : 5, x: 0, y: strong ? 4 : 2)
            .shadow(color: .black.opacity(strong ? 0.45 : 0.28), radius: strong ? 30 : 18, x: 0, y: strong ? 16 : 9)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.04)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8
                    )
            )
    }
}
