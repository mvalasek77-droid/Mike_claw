import CoreGraphics

/// Translates raw watchOS gestures + Crown rotation into engine `Intent`s,
/// using only inputs third-party watchOS apps can actually read
/// (Crown rotation + touchscreen). See DESIGN.md "Platform reality check".
struct InputController {

    /// Crown rotation accumulates; once it crosses a small threshold we emit a
    /// charge intent sized by the rotation speed (fast spin == faster charge,
    /// matching the analog dial concept).
    static func crownIntent(delta: CGFloat) -> Intent? {
        guard abs(delta) > 0.001 else { return nil }
        return .charge(delta)
    }

    /// A tap maps to light (top half of the screen) or heavy (bottom half).
    static func tapIntent(at point: CGPoint, in size: CGSize) -> Intent {
        point.y < size.height / 2 ? .lightAttack : .heavyAttack
    }

    /// Horizontal swipes step; an upward swipe jumps; a downward swipe parries.
    static func swipeIntent(dx: CGFloat, dy: CGFloat) -> Intent? {
        if abs(dx) > abs(dy) {
            return dx > 0 ? .stepForward : .stepBack
        }
        return dy > 0 ? .jump : .parry   // SpriteKit y-up: dy>0 up, dy<0 down=parry
    }
}
