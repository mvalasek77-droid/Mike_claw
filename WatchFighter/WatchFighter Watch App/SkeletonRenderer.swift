#if os(watchOS)
import SpriteKit

/// Draws a fighter as a smoothed stick-skeleton built from `Pose` joint points.
/// Limbs are capsules (rounded line nodes) + a head; an accent "gi/trim" line
/// gives each character their colour. This replaces the placeholder rectangle
/// and is driven entirely by the pure `Animator`, so it stays netplay-safe.
final class SkeletonRenderer {
    let root = SKNode()

    private let spine = SKShapeNode()
    private let frontArm = SKShapeNode()
    private let backArm = SKShapeNode()
    private let frontLeg = SKShapeNode()
    private let backLeg = SKShapeNode()
    private let head = SKShapeNode(circleOfRadius: 6)
    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 30, height: 7))

    private var current: Pose
    private let body: SKColor
    private let accent: SKColor

    init(spec: CharacterSpec) {
        body = spec.bodyColor.skColor
        accent = spec.accentColor.skColor
        current = Animator.idle(clock: 0)

        shadow.fillColor = SKColor(white: 0, alpha: 0.35)
        shadow.strokeColor = .clear
        shadow.zPosition = -1
        root.addChild(shadow)

        for limb in [backLeg, backArm, spine, frontLeg, frontArm] {
            limb.strokeColor = body
            limb.lineWidth = 6
            limb.lineCap = .round
            root.addChild(limb)
        }
        // Front limbs get the accent colour so the silhouette reads clearly.
        frontArm.strokeColor = accent
        frontLeg.strokeColor = accent

        head.fillColor = body
        head.strokeColor = accent
        head.lineWidth = 2
        root.addChild(head)
    }

    /// Update the skeleton from a fighter snapshot. `originX`/`groundY` place the
    /// feet; `facing` flips the forward axis; `flashHit` whitens on impact.
    func update(for f: Fighter, clock: CGFloat, originX: CGFloat, groundY: CGFloat,
                flashHit: Bool) {
        let target = Animator.pose(for: f, clock: clock)
        // Smooth toward the target to avoid popping between states.
        current = current.lerp(to: target, 0.4)

        let facing: CGFloat = f.facingRight ? 1 : -1
        func P(_ p: CGPoint) -> CGPoint {
            CGPoint(x: originX + p.x * facing, y: groundY + p.y)
        }

        let pelvis = P(current.pelvis), chest = P(current.chest), headP = P(current.head)
        spine.path = segment(pelvis, chest)
        head.position = headP

        frontArm.path = segment(chest, P(current.frontHand))
        backArm.path = segment(chest, P(current.backHand))
        frontLeg.path = segment(pelvis, P(current.frontFoot))
        backLeg.path = segment(pelvis, P(current.backFoot))

        shadow.position = CGPoint(x: originX, y: groundY + 1)

        let hit = flashHit || f.state == .hitStun || f.state == .launched
        let blocking = f.isBlocking
        root.alpha = blocking ? 0.7 : 1
        let limbColor = hit ? SKColor.white : body
        spine.strokeColor = limbColor
        backArm.strokeColor = limbColor
        backLeg.strokeColor = limbColor
        frontArm.strokeColor = hit ? .white : accent
        frontLeg.strokeColor = hit ? .white : accent
        head.fillColor = hit ? .white : body
    }

    private func segment(_ a: CGPoint, _ b: CGPoint) -> CGPath {
        let p = CGMutablePath()
        p.move(to: a); p.addLine(to: b)
        return p
    }
}
#endif
