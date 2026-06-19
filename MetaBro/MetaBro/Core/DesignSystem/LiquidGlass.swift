import SwiftUI

/// MetaBro's Liquid Glass surface treatment: translucent, vibrancy-aware,
/// with a hairline specular edge. Respects Reduce Transparency by falling
/// back to a solid surface (accessibility requirement, not optional).
struct LiquidGlass: ViewModifier {
    var radius: CGFloat = Tokens.Radius.lg
    var strokeOpacity: Double = 0.18

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                if reduceTransparency {
                    shape.fill(.background)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .overlay {
                // Hairline specular edge — soft light along the glass rim.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(reduceTransparency ? 0 : strokeOpacity),
                                .white.opacity(0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    /// Wraps the view in a Liquid Glass surface.
    func liquidGlass(radius: CGFloat = Tokens.Radius.lg) -> some View {
        modifier(LiquidGlass(radius: radius))
    }
}
