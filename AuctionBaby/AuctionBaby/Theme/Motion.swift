import SwiftUI
import UIKit

/// Animation curves and a light haptics layer, all Reduce-Motion aware via
/// ``Motion/run(_:_:)`` so the app honours accessibility settings everywhere.
enum Motion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snap = Animation.spring(response: 0.26, dampingFraction: 0.86)
    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.62)
    static let smooth = Animation.easeInOut(duration: 0.45)

    static func run(_ animation: Animation, _ body: () -> Void) {
        if UIAccessibility.isReduceMotionEnabled {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t, body)
        } else {
            withAnimation(animation, body)
        }
    }
}

/// Adaptive haptics. Centralised so every tap/commit/win uses a consistent,
/// tasteful feedback vocabulary — and so we can mute it in one place.
enum Haptics {
    static func tap() { impact(.light) }
    static func commit() { impact(.medium) }
    static func heavy() { impact(.heavy) }

    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error() { notify(.error) }

    static func selection() {
        let g = UISelectionFeedbackGenerator()
        g.prepare(); g.selectionChanged()
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare(); g.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let g = UINotificationFeedbackGenerator()
        g.prepare(); g.notificationOccurred(type)
    }
}

extension View {
    @ViewBuilder
    func motion(_ animation: Animation, value: some Equatable) -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            self
        } else {
            self.animation(animation, value: value)
        }
    }

    /// Entrance: content rises and fades in on first appearance. Staggering
    /// the `delay` per row gives lists a lively, orchestrated arrival.
    func riseIn(_ delay: Double = 0) -> some View { modifier(RiseIn(delay: delay)) }
}

struct RiseIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .onAppear {
                guard !shown else { return }
                Motion.run(Motion.spring.delay(delay)) { shown = true }
            }
    }
}
