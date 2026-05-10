import SwiftUI

/// Animation curves used across CodeGenie.
///
/// Every curve here passes through ``Motion.respect(_:)`` when used inside
/// a view, which collapses to ``.linear(duration: 0)`` if the user has
/// "Reduce Motion" enabled in iOS Accessibility. The result is that
/// every transition is one-source-of-truth and Reduce-Motion-correct.
enum Motion {
    /// Tap / state-change spring (Music + Wallet feel).
    static let spring  = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// Sheet / route fade.
    static let smooth  = Animation.smooth(duration: 0.55)
    /// Fast micro-feedback (chip press, tab swap).
    static let snap    = Animation.spring(response: 0.25, dampingFraction: 0.85)
    /// Slow drifting (background orbs, splash reveal).
    static let drift   = Animation.easeInOut(duration: 2.6)

    /// Runs `body` inside a `withAnimation` that honours Reduce Motion.
    static func run(_ animation: Animation, _ body: () -> Void) {
        if UIAccessibility.isReduceMotionEnabled {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, body)
        } else {
            withAnimation(animation, body)
        }
    }
}

extension View {
    /// Apply an animation that becomes a no-op under Reduce Motion.
    @ViewBuilder
    func motion(_ animation: Animation, value: some Equatable) -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            self
        } else {
            self.animation(animation, value: value)
        }
    }
}
