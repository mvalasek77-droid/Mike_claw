import SwiftUI

/// Consolidated VoiceOver labels + Dynamic Type helpers so critical
/// controls read cleanly with the Rotor and Reader turned on.
extension View {
    /// Announces a chart data-point summary since Canvas doesn't
    /// expose per-element accessibility by default.
    func accessibleChart(_ summary: String) -> some View {
        self.accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// Announces a signed monetary value in the natural "gained /
    /// lost N Reel Coins" phrasing so VoiceOver doesn't say "minus
    /// three point one four RC".
    func accessibleCoinDelta(_ value: Double) -> some View {
        let verb = value >= 0 ? "gained" : "lost"
        let n = String(format: "%.0f", abs(value))
        return accessibilityLabel("\(verb) \(n) Reel Coins")
    }
}

/// Preferred size-category clamp for charts so Dynamic Type can't
/// blow up the axis labels past readability.
struct ClampDynamicType: ViewModifier {
    let max: DynamicTypeSize
    func body(content: Content) -> some View {
        content.dynamicTypeSize(...max)
    }
}
extension View {
    func clampDynamicType(_ max: DynamicTypeSize = .accessibility1) -> some View {
        modifier(ClampDynamicType(max: max))
    }
}
