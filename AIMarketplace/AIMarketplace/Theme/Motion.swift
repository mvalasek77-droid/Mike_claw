import SwiftUI

/// Animation curves, all Reduce-Motion aware via ``Motion/run(_:_:)``.
enum Motion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snap = Animation.spring(response: 0.26, dampingFraction: 0.86)
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
