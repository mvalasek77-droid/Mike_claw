import SwiftUI

// MARK: - BareClaw Design System
//
// Single source of truth for motion, haptics, button styles, and glass effects.
// Color palette, typography, spacing, and hex init live in HermesTheme.swift.

// MARK: - Typography (Font.BC — distinct from Color.BC in HermesTheme)

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
}

// MARK: - Accessible Button Style

struct BCButtonStyle: ButtonStyle {
    var haptic: BCHapticStyle = .light

    enum BCHapticStyle { case light, medium, heavy, none }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(BCMotion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
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

