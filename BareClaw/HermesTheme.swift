import SwiftUI

// MARK: - BareClaw Theme
//
// Dark, focused aesthetic inspired by a terminal / IDE feel.
// Primary brand colour: Electric Blue  (#0A84FF → system)
// Accent:              Amber Claw      (#FF9F0A)
// Background:          Midnight Navy   (#0D1117)
// Surface:             Deep Slate      (#161B22)
// Border:              Ghost Rail      (#30363D)

// MARK: - Colour palette

extension Color {
    enum BC {
        // Backgrounds
        static let background    = Color(hex: "#0D1117")   // Midnight Navy
        static let surface       = Color(hex: "#161B22")   // Deep Slate
        static let surfaceRaised = Color(hex: "#1C2128")   // Card / sheet layer
        static let border        = Color(hex: "#30363D")   // Ghost Rail

        // Brand
        static let primary       = Color(hex: "#2F81F7")   // Electric Blue
        static let accent        = Color(hex: "#FF9F0A")   // Amber Claw
        static let accentSoft    = Color(hex: "#FF9F0A").opacity(0.15)

        // Text
        static let textPrimary   = Color(hex: "#E6EDF3")
        static let textSecondary = Color(hex: "#8B949E")
        static let textMuted     = Color(hex: "#484F58")

        // Aliases — used in some views for clarity
        static var primaryText:   Color { textPrimary }
        static var secondaryText: Color { textSecondary }

        // Semantic
        static let success        = Color(hex: "#3FB950")
        static let warning        = Color(hex: "#D29922")
        static let danger         = Color(hex: "#F85149")
        static let info           = Color(hex: "#58A6FF")

        // Dream mode highlight
        static let dreamPurple    = Color(hex: "#BC8CFF")
        static let dreamPurpleSoft = Color(hex: "#BC8CFF").opacity(0.12)
    }
}

// MARK: - Typography

enum BCFont {
    static func title(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static func headline(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
    static func body(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
    static func footnote(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    static func mono(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

// MARK: - Spacing & radius

enum BCSizing {
    static let radiusSM: CGFloat  = 6
    static let radiusMD: CGFloat  = 10
    static let radiusLG: CGFloat  = 16
    static let radiusXL: CGFloat  = 24

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 36
}

// MARK: - Common view modifiers

struct BCCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.BC.surfaceRaised)
            .cornerRadius(BCSizing.radiusMD)
            .overlay(
                RoundedRectangle(cornerRadius: BCSizing.radiusMD)
                    .strokeBorder(Color.BC.border, lineWidth: 1)
            )
    }
}

struct BCAccentBadge: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, BCSizing.spacingSM)
            .padding(.vertical, BCSizing.spacingXS)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(BCSizing.radiusSM)
            .font(BCFont.caption())
    }
}

extension View {
    func bcCard() -> some View { modifier(BCCardStyle()) }
    func bcBadge(_ color: Color = .BC.accent) -> some View { modifier(BCAccentBadge(color: color)) }

    /// Conditionally applies a transform — used to toggle clipShape and other modifiers.
    @ViewBuilder
    func applyIf<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Hex colour convenience

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
