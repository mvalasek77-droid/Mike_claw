import SwiftUI

/// CodeGenie's Liquid Glass design system, tuned for iOS 26.
///
/// Centralises the materials, gradients and motion curves used across the
/// product so every screen reads as the same family. We lean on Apple's
/// `.glassEffect()` modifier when available (iOS 26+), and fall back to
/// `.ultraThinMaterial` everywhere else so the app still ships a coherent
/// look on iOS 17–25.
enum LiquidGlass {
    static let accent = Color(red: 0.36, green: 0.49, blue: 1.0)
    static let accentSecondary = Color(red: 0.71, green: 0.41, blue: 1.0)
    static let success = Color(red: 0.30, green: 0.84, blue: 0.55)
    static let warning = Color(red: 1.00, green: 0.71, blue: 0.20)

    static let cornerLarge: CGFloat = 28
    static let cornerMedium: CGFloat = 18
    static let cornerSmall: CGFloat = 12

    static let baseGradient = LinearGradient(
        colors: [
            Color(red: 0.07, green: 0.09, blue: 0.18),
            Color(red: 0.12, green: 0.10, blue: 0.24),
            Color(red: 0.04, green: 0.07, blue: 0.14)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let auroraGradient = LinearGradient(
        colors: [accent, accentSecondary, success],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Smooth motion curve we use for sheet/route transitions and pressable
    /// tactile feedback. Matches the spring Apple uses in Music + Wallet.
    static let motion: Animation = .spring(response: 0.42, dampingFraction: 0.82)
}

struct LiquidGlassBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LiquidGlass.baseGradient

            // Slow drifting orbs that give the screen depth without
            // distracting from content. Frozen at a pleasant pose under
            // Reduce Motion so we don't burn battery on a TimelineView
            // the user explicitly opted out of.
            if reduceMotion {
                Canvas { ctx, size in
                    drawOrb(in: ctx, size: size, t: 0,    hueShift: 0)
                    drawOrb(in: ctx, size: size, t: 5,    hueShift: 0.18)
                    drawOrb(in: ctx, size: size, t: 11,   hueShift: -0.12)
                }
                .blendMode(.screen)
                .opacity(0.45)
                .accessibilityHidden(true)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    Canvas { ctx, size in
                        let t = context.date.timeIntervalSinceReferenceDate
                        drawOrb(in: ctx, size: size, t: t, hueShift: 0)
                        drawOrb(in: ctx, size: size, t: t + 5, hueShift: 0.18)
                        drawOrb(in: ctx, size: size, t: t + 11, hueShift: -0.12)
                    }
                }
                .blendMode(.screen)
                .opacity(0.55)
                .accessibilityHidden(true)
            }

            // Subtle vignette for legibility
            RadialGradient(
                colors: [.clear, .black.opacity(0.35)],
                center: .center,
                startRadius: 200,
                endRadius: 700
            )
            .blendMode(.multiply)
            .allowsHitTesting(false)
        }
    }

    private func drawOrb(in ctx: GraphicsContext, size: CGSize, t: TimeInterval, hueShift: Double) {
        let cx = size.width  * (0.5 + 0.32 * CGFloat(sin(t * 0.07)))
        let cy = size.height * (0.5 + 0.34 * CGFloat(cos(t * 0.05)))
        let radius = max(size.width, size.height) * 0.55
        let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
        let color = Color(hue: 0.62 + hueShift, saturation: 0.85, brightness: 0.95).opacity(0.22)
        ctx.fill(Path(ellipseIn: rect), with: .color(color))
    }
}

// MARK: - Glass surface

struct GlassSurface<Content: View>: View {
    enum Tier { case raised, flat, deep }

    var tier: Tier = .raised
    var corner: CGFloat = LiquidGlass.cornerLarge
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                ZStack {
                    if #available(iOS 26.0, *) {
                        // iOS 26 Liquid Glass: dynamic refraction + tint
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(.regularMaterial)
                            .glassEffectIfAvailable()
                    } else {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }

                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: tintColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .opacity(tier == .deep ? 0.20 : 0.12)
                        .blendMode(.plusLighter)

                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
            }
            .compositingGroup()
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var tintColors: [Color] {
        switch tier {
        case .raised: return [LiquidGlass.accent.opacity(0.45), LiquidGlass.accentSecondary.opacity(0.35)]
        case .flat:   return [.white.opacity(0.10), .white.opacity(0.02)]
        case .deep:   return [LiquidGlass.accentSecondary.opacity(0.35), LiquidGlass.accent.opacity(0.20)]
        }
    }

    private var shadowColor: Color {
        switch tier {
        case .raised: return .black.opacity(0.35)
        case .flat:   return .black.opacity(0.15)
        case .deep:   return .black.opacity(0.45)
        }
    }
    private var shadowRadius: CGFloat { tier == .deep ? 28 : 16 }
    private var shadowY: CGFloat { tier == .deep ? 14 : 8 }
}

// Wrapper so the file still compiles on Xcode versions without iOS 26 SDK
// — the modifier becomes a no-op rather than a build failure.
private extension View {
    @ViewBuilder
    func glassEffectIfAvailable() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: 28))
        } else {
            self
        }
        #else
        self
        #endif
    }
}
