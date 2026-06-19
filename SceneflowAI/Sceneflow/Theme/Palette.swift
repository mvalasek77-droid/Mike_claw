import SwiftUI

/// Sceneflow's design system — a focused, cinematic dark-first palette tuned
/// for long writing sessions. We lean on Apple's `.glassEffect()` (iOS 26+)
/// where available and fall back to `.ultraThinMaterial` everywhere else so
/// the product reads as one coherent family on iOS 17–25.
enum Palette {
    /// Warm amber — the "marquee" accent. Evokes a cinema light without the
    /// fintech-purple cliché.
    static let accent = Color(red: 0.957, green: 0.671, blue: 0.286)
    static let accentDeep = Color(red: 0.886, green: 0.482, blue: 0.196)
    static let ink = Color(red: 0.36, green: 0.49, blue: 1.0)
    static let success = Color(red: 0.30, green: 0.84, blue: 0.55)
    static let warning = Color(red: 1.00, green: 0.71, blue: 0.20)
    static let danger = Color(red: 0.96, green: 0.36, blue: 0.42)

    static let primaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .light
            ? UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
            : UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)
    })

    static let secondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .light
            ? UIColor(white: 0.36, alpha: 1.0)
            : UIColor(white: 0.68, alpha: 1.0)
    })

    static let cornerLarge: CGFloat = 26
    static let cornerMedium: CGFloat = 16
    static let cornerSmall: CGFloat = 10

    static let darkBaseGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.06, blue: 0.09),
            Color(red: 0.09, green: 0.08, blue: 0.12),
            Color(red: 0.05, green: 0.05, blue: 0.07)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let lightBaseGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.97, blue: 0.95),
            Color(red: 0.95, green: 0.94, blue: 0.92),
            Color(red: 0.99, green: 0.97, blue: 0.94)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let marqueeGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let motion: Animation = .spring(response: 0.42, dampingFraction: 0.82)
}

struct AmbientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .light ? Palette.lightBaseGradient : Palette.darkBaseGradient)

            if reduceMotion {
                Canvas { ctx, size in
                    drawGlow(in: ctx, size: size, t: 0)
                }
                .blendMode(.screen)
                .opacity(colorScheme == .light ? 0.20 : 0.35)
                .accessibilityHidden(true)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    Canvas { ctx, size in
                        drawGlow(in: ctx, size: size, t: context.date.timeIntervalSinceReferenceDate)
                    }
                }
                .blendMode(.screen)
                .opacity(colorScheme == .light ? 0.22 : 0.42)
                .accessibilityHidden(true)
            }

            RadialGradient(
                colors: [.clear, colorScheme == .light ? .black.opacity(0.06) : .black.opacity(0.35)],
                center: .center,
                startRadius: 220,
                endRadius: 720
            )
            .blendMode(.multiply)
            .allowsHitTesting(false)
        }
    }

    private func drawGlow(in ctx: GraphicsContext, size: CGSize, t: TimeInterval) {
        let cx = size.width * (0.5 + 0.30 * CGFloat(sin(t * 0.06)))
        let cy = size.height * (0.32 + 0.22 * CGFloat(cos(t * 0.04)))
        let radius = max(size.width, size.height) * 0.5
        let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(Palette.accent.opacity(0.16)))
    }
}

// MARK: - Glass surface

/// Visual elevation of a glass surface. Top-level (not nested in the generic
/// `GlassSurface`) so it can be referenced without specializing the generic.
enum GlassTier { case raised, flat, deep }

struct GlassSurface<Content: View>: View {
    var tier: GlassTier = .raised
    var corner: CGFloat = Palette.cornerLarge
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffectIfAvailable(corner: corner)

                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: tintColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .opacity(tier == .deep ? 0.18 : 0.10)
                        .blendMode(.plusLighter)

                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.45), .white.opacity(0.04)],
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
        case .raised: return [Palette.accent.opacity(0.35), Palette.accentDeep.opacity(0.20)]
        case .flat:   return [.white.opacity(0.08), .white.opacity(0.02)]
        case .deep:   return [Palette.accentDeep.opacity(0.30), Palette.accent.opacity(0.14)]
        }
    }

    private var shadowColor: Color {
        switch tier {
        case .raised: return .black.opacity(0.30)
        case .flat:   return .black.opacity(0.12)
        case .deep:   return .black.opacity(0.42)
        }
    }
    private var shadowRadius: CGFloat { tier == .deep ? 26 : 14 }
    private var shadowY: CGFloat { tier == .deep ? 13 : 7 }
}

private extension View {
    /// Becomes a no-op on Xcode versions without the iOS 26 SDK rather than a
    /// build failure.
    @ViewBuilder
    func glassEffectIfAvailable(corner: CGFloat) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else {
            self
        }
        #else
        self
        #endif
    }
}
