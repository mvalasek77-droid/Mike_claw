import SwiftUI

/// Animation curves used across Sceneflow. Every curve collapses to a no-op
/// when the user has "Reduce Motion" enabled, so transitions are
/// one-source-of-truth and accessibility-correct.
enum Motion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let smooth = Animation.smooth(duration: 0.5)
    static let snap = Animation.spring(response: 0.25, dampingFraction: 0.85)

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
    @ViewBuilder
    func motion(_ animation: Animation, value: some Equatable) -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            self
        } else {
            self.animation(animation, value: value)
        }
    }
}
