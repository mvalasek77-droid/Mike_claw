import SwiftUI

/// The BoxCall design system. Single source of truth for colors,
/// spacing, radii, motion, and surface treatments. Every accent value
/// lives here so a redesign is one file.
///
/// Surfaces use iOS 26's Liquid Glass (`glassEffect`) on-device and
/// gracefully fall back to `Material.ultraThinMaterial` on 17-25.
enum Theme {

    // MARK: - Palette (semantic — light + dark identical for now)
    static let accent   = Color(red: 1.0,  green: 0.55, blue: 0.12)   // BoxCall orange
    static let accentSoft = Color(red: 1.0, green: 0.69, blue: 0.4)
    static let bull    = Color(red: 0.29, green: 0.87, blue: 0.50)    // profit / call
    static let bear    = Color(red: 0.94, green: 0.27, blue: 0.27)    // loss / put
    static let neutral  = Color(white: 0.55)

    // Reputation-tier colors mirror Tier.color but sourced from theme.
    static let tierRookie      = Color.gray
    static let tierAnalyst     = Color.blue
    static let tierInsider     = Color.yellow
    static let tierProducer    = Color.purple
    static let tierStudioHead  = Color.pink
    static let tierOracle      = Color.orange

    // MARK: - Radii (matches iOS 26 continuous corner curve)
    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    // MARK: - Spacing scale (4-pt grid)
    enum Space {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Motion
    enum Motion {
        static let snap:    Animation = .spring(response: 0.28, dampingFraction: 0.85)
        static let smooth:  Animation = .spring(response: 0.45, dampingFraction: 0.86)
        static let breathe: Animation = .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
        static let toast:   Animation = .spring(response: 0.36, dampingFraction: 0.75)
    }
}

// MARK: - Glass surface modifier

/// A card / sheet surface that uses iOS 26 Liquid Glass when
/// available, and Material.ultraThinMaterial as a graceful fallback.
/// Callers pass a corner radius so it can nest inside any layout.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.md
    var tint: Color? = nil
    var stroke: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(background)
            .overlay(strokeShape)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Liquid Glass — depth + refraction handled by the system.
            shape.glassEffect(.regular.tint(tint ?? .clear.opacity(0.001)))
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(tint?.opacity(0.10) ?? .clear))
        }
        #else
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(tint?.opacity(0.10) ?? .clear))
        #endif
    }

    @ViewBuilder
    private var strokeShape: some View {
        if let stroke {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        }
    }
}

extension View {
    /// Wrap content in a Liquid Glass surface (falls back on iOS < 26).
    func glassSurface(radius: CGFloat = Theme.Radius.md,
                      tint: Color? = nil,
                      stroke: Color? = nil) -> some View {
        modifier(GlassSurface(cornerRadius: radius, tint: tint, stroke: stroke))
    }
}

// MARK: - Depth pressable button style

/// A press-in-with-a-satisfying-drop button style. Uses spring motion
/// + subtle shadow so tap targets feel physical, not flat.
struct DepthButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.85 : 1))
            )
            .foregroundStyle(tint == .clear ? .primary : Color.black.opacity(0.85))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.10 : 0.25),
                    radius: configuration.isPressed ? 4 : 10,
                    y: configuration.isPressed ? 2 : 6)
            .animation(Theme.Motion.snap, value: configuration.isPressed)
    }
}
