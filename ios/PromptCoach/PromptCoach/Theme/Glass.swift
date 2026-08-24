import SwiftUI
import UIKit

/// Prompt Coach's Liquid Glass design system, kept deliberately close to the
/// CodeGenie app so the two read as the same family. Materials + iOS 26
/// `glassEffect` with a graceful `.ultraThinMaterial` fallback.
enum Glass {
    static let accent = Color(red: 0.36, green: 0.49, blue: 1.0)
    static let accentSecondary = Color(red: 0.71, green: 0.41, blue: 1.0)
    static let success = Color(red: 0.30, green: 0.84, blue: 0.55)
    static let warning = Color(red: 1.00, green: 0.71, blue: 0.20)

    /// One accent per model, so the screen subtly re-tints when the target
    /// changes. Keys match `model-pack.json` ids; the contract test in
    /// Tests/validate_pack.py asserts every model in the pack has a tint.
    static func tint(for modelID: String) -> Color {
        switch modelID {
        case "claude-haiku-4-5": return Color(red: 1.00, green: 0.74, blue: 0.28) // amber
        case "claude-sonnet-5":  return Color(red: 0.22, green: 0.80, blue: 0.76) // teal
        case "claude-opus-5":    return Color(red: 0.44, green: 0.44, blue: 0.98) // indigo
        case "claude-opus-4-8":  return Color(red: 0.52, green: 0.56, blue: 0.66) // slate (legacy tier)
        case "claude-fable-5":   return Color(red: 0.98, green: 0.45, blue: 0.28) // ember
        default:                 return accent
        }
    }

    static let primaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .light
            ? UIColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1.0)
            : UIColor.white
    })

    static let cornerLarge: CGFloat = 26
    static let cornerMedium: CGFloat = 16

    static let motion: Animation = .spring(response: 0.42, dampingFraction: 0.82)
    static let snap: Animation = .spring(response: 0.25, dampingFraction: 0.85)
}

/// Drifting-gradient background, frozen under Reduce Motion.
struct GlassBackground: View {
    var tint: Color = Glass.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            base
            if reduceMotion {
                Canvas { ctx, size in orb(ctx, size, 0, tint) }
                    .blendMode(.screen).opacity(scheme == .light ? 0.28 : 0.42)
                    .accessibilityHidden(true)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                    Canvas { g, size in orb(g, size, ctx.date.timeIntervalSinceReferenceDate, tint) }
                }
                .blendMode(.screen).opacity(scheme == .light ? 0.32 : 0.5)
                .accessibilityHidden(true)
            }
        }
        .animation(Glass.motion, value: tint)
    }

    private var base: some View {
        LinearGradient(
            colors: scheme == .light
                ? [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.92, green: 0.94, blue: 1.0)]
                : [Color(red: 0.06, green: 0.08, blue: 0.16), Color(red: 0.03, green: 0.05, blue: 0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private func orb(_ ctx: GraphicsContext, _ size: CGSize, _ t: TimeInterval, _ color: Color) {
        let cx = size.width  * (0.5 + 0.30 * CGFloat(sin(t * 0.07)))
        let cy = size.height * (0.4 + 0.32 * CGFloat(cos(t * 0.05)))
        let r = max(size.width, size.height) * 0.6
        ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                 with: .color(color.opacity(0.28)))
    }
}

/// Frosted glass card used for every surface.
struct GlassCard<Content: View>: View {
    var corner: CGFloat = Glass.cornerLarge
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassIfAvailable(corner: corner)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 0.8)
                }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
    }
}

private extension View {
    @ViewBuilder
    func glassIfAvailable(corner: CGFloat) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: corner))
        } else { self }
        #else
        self
        #endif
    }
}

/// Typography that scales with Dynamic Type.
///
/// Deliberately built on text styles rather than fixed point sizes: a
/// `.system(size: 14)` font ignores the user's text-size setting entirely,
/// which fails accessibility review. These keep the rounded design while
/// still responding to Larger Text.
enum Type {
    static let hero      = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let title     = Font.system(.title2,     design: .rounded).weight(.bold)
    static let heading   = Font.system(.title3,     design: .rounded).weight(.semibold)
    static let cardTitle = Font.system(.headline,   design: .rounded)
    static let body      = Font.system(.body,       design: .rounded)
    static let bodyMed   = Font.system(.body,       design: .rounded).weight(.medium)
    static let secondary = Font.system(.subheadline, design: .rounded)
    static let label     = Font.system(.footnote,   design: .rounded).weight(.semibold)
    static let caption   = Font.system(.caption,    design: .rounded)
    static let captionB  = Font.system(.caption2,   design: .rounded).weight(.bold)
    static let mono      = Font.system(.footnote,   design: .monospaced)
}

/// Adaptive haptics.
///
/// Wraps UIKit's feedback generators. Each call creates a fresh generator so
/// there is no retained state to go stale between screens; the cost is
/// negligible next to the haptic itself. Silently no-ops on hardware without
/// a Taptic Engine, which is the platform's own behaviour.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
