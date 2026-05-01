import SwiftUI

// MARK: - BareClaw Design System
//
// Single source of truth for color, typography, motion, haptics, and glass effects.
// Every pixel in the app should source from here. No hardcoded hex values in views.

// MARK: - Color Palette

extension Color {
    enum BC {
        // MARK: Brand
        static let forest        = Color("BCForest",        bundle: nil)
        static let forestMid     = Color("BCForestMid",     bundle: nil)
        static let gold          = Color("BCGold",          bundle: nil)
        static let cream         = Color("BCCream",         bundle: nil)
        static let warmWhite     = Color("BCWarmWhite",     bundle: nil)
        static let tan           = Color("BCTan",           bundle: nil)
        static let purple        = Color("BCPurple",        bundle: nil)

        // MARK: Text
        static let textPrimary   = Color("BCTextPrimary",   bundle: nil)
        static let textSecondary = Color("BCTextSecondary", bundle: nil)
        static let textTertiary  = Color("BCTextTertiary",  bundle: nil)

        // MARK: Surface
        static let surface        = Color("BCSurface",       bundle: nil)
        static let surfaceRaised  = Color("BCSurfaceRaised", bundle: nil)
        static let surfaceOverlay = Color("BCSurfaceOverlay",bundle: nil)

        // MARK: Semantic
        static let destructive   = Color.red
        static let success       = Color(hex: "#30D158")
        static let warning       = Color(hex: "#FF9F0A")

        // MARK: Hex fallbacks (used while ColorSet assets are added to Xcode)
        // These match the light-mode palette already in the app.
        static var _forest:    Color { Color(hex: "#1E3932") }
        static var _forestMid: Color { Color(hex: "#2C5147") }
        static var _gold:      Color { Color(hex: "#CBA258") }
        static var _cream:     Color { Color(hex: "#F2F0EB") }
        static var _warmWhite: Color { Color(hex: "#FAF7F2") }
        static var _tan:       Color { Color(hex: "#E8E0D0") }
        static var _purple:    Color { Color(hex: "#7B68EE") }
        static var _textPrimary:   Color { Color(hex: "#1E3932") }
        static var _textSecondary: Color { Color(hex: "#5C5C5C") }
        static var _textTertiary:  Color { Color(hex: "#9A9A9A") }
        static var _surface:       Color { Color(hex: "#FFFFFF") }
        static var _surfaceRaised: Color { Color(hex: "#F2F0EB") }
    }
}

// MARK: - Typography

extension Font {
    enum BC {
        static func display(_ size: CGFloat = 34, weight: Font.Weight = .black) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        static func title(_ size: CGFloat = 22, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        static func headline(_ size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        static func caption(_ size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
        static func micro(_ size: CGFloat = 10, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }
}

// MARK: - Motion

enum BCMotion {
    // Interactive (button presses, card taps)
    static let interactive   = Animation.spring(response: 0.32, dampingFraction: 0.72)
    // Expansive (modals, full-screen transitions)
    static let expansive     = Animation.spring(response: 0.50, dampingFraction: 0.78)
    // Snappy (toggles, pills)
    static let snappy        = Animation.spring(response: 0.22, dampingFraction: 0.80)
    // Gentle (ambient, background changes)
    static let gentle        = Animation.easeInOut(duration: 0.38)
    // Reveal (onboarding reveals, ceremony)
    static let reveal        = Animation.spring(response: 0.60, dampingFraction: 0.70)
}

// MARK: - Haptics

enum BCHaptic {
    static func light()     { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium()    { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy()     { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func rigid()     { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func soft()      { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success()   { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning()   { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()     { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Liquid Glass (iOS 26)

struct LiquidGlassModifier: ViewModifier {
    var radius: CGFloat     = 18
    var padding: CGFloat    = 16
    var tint: Color         = .white.opacity(0.05)

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                if #available(iOS 26.0, *) {
                    // Native Liquid Glass when on iOS 26
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(tint)
                        }
                } else {
                    // iOS 17/18 fallback — frosted glass effect
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        }
                }
            }
    }
}

struct GlassCardModifier: ViewModifier {
    var radius: CGFloat  = 18
    var shadow: Bool     = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(
                        color: shadow ? .black.opacity(0.08) : .clear,
                        radius: shadow ? 12 : 0,
                        y: shadow ? 4 : 0
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            }
    }
}

extension View {
    func liquidGlass(radius: CGFloat = 18, padding: CGFloat = 16, tint: Color = .white.opacity(0.05)) -> some View {
        modifier(LiquidGlassModifier(radius: radius, padding: padding, tint: tint))
    }

    func glassCard(radius: CGFloat = 18, shadow: Bool = true) -> some View {
        modifier(GlassCardModifier(radius: radius, shadow: shadow))
    }

    /// Applies standard BareClaw card styling (solid white card, rounded corners, shadow).
    func bcCard(radius: CGFloat = 16) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.BC._surface)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
    }
}

// MARK: - Accessible Button Style

struct BCButtonStyle: ButtonStyle {
    var haptic: BCHapticStyle = .light

    enum BCHapticStyle { case light, medium, heavy, none }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(BCMotion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed {
                    switch haptic {
                    case .light:  BCHaptic.light()
                    case .medium: BCHaptic.medium()
                    case .heavy:  BCHaptic.heavy()
                    case .none:   break
                    }
                }
            }
    }
}

extension View {
    func bcButton(haptic: BCButtonStyle.BCHapticStyle = .light) -> some View {
        buttonStyle(BCButtonStyle(haptic: haptic))
    }
}

// MARK: - Depth Shadow

extension View {
    func depthShadow(opacity: Double = 0.12, radius: CGFloat = 16, y: CGFloat = 6) -> some View {
        self.shadow(color: .black.opacity(opacity), radius: radius, y: y)
    }
}

// MARK: - Shimmer (loading placeholder)

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.45), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: phase * (geo.size.width + 200) - 100)
                }
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Pulse animation

struct PulseModifier: ViewModifier {
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    scale = 1.06
                }
            }
    }
}

extension View {
    func pulse() -> some View { modifier(PulseModifier()) }
}

// MARK: - applyIf helper (already in codebase, keep compatible)

extension View {
    @ViewBuilder
    func applyIf<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
