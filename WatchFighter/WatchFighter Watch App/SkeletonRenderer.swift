#if os(watchOS)
import SpriteKit

extension RGBA {
    // `skColor` is defined in StageBuilder.swift.
    /// A darkened version for outlines/shading.
    func darkened(_ k: CGFloat = 0.3) -> SKColor { SKColor(red: r * k, green: g * k, blue: b * k, alpha: 1) }
}

/// Anything that can draw a fighter. Lets `FightScene` use either the procedural
/// `SkeletonRenderer` (always available) or a `SpriteFighter` (when real art is
/// present) behind one interface.
protocol FighterRenderer: AnyObject {
    var root: SKNode { get }
    func update(for f: Fighter, clock: CGFloat, originX: CGFloat, groundY: CGFloat, flashHit: Bool)
}

/// Procedural fighter: an outlined, shaded figure with body mass — a real step
/// up from stick lines, and the automatic fallback when no sprite art exists.
/// Driven entirely by the pure `Animator`, so it stays netplay-safe.
final class SkeletonRenderer: FighterRenderer {
    let root = SKNode()

    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 30, height: 7))
    private let torsoOutline = SKShapeNode()
    private let torso = SKShapeNode()
    private let backArmO = SKShapeNode(), backArm = SKShapeNode()
    private let backLegO = SKShapeNode(), backLeg = SKShapeNode()
    private let frontLegO = SKShapeNode(), frontLeg = SKShapeNode()
    private let frontArmO = SKShapeNode(), frontArm = SKShapeNode()
    private let head = SKShapeNode(circleOfRadius: 6.5)

    // Generative extras (no assets): a dynamic rim-light glow + a verlet ribbon.
    private let glow = SKSpriteNode()
    private let ribbonNode = SKShapeNode()
    private var ribbon: [CGPoint] = []
    private var ribbonPrev: [CGPoint] = []
    private var ribbonSeeded = false
    private let ribbonCount = 9
    private let ribbonSeg: CGFloat = 5

    private var current: Pose
    private let body: SKColor, accent: SKColor, outline: SKColor

    /// Soft radial-gradient sprite, generated once with Core Graphics — used for
    /// the rim/impact light. Pure code, no art file.
    static let softGlow: SKTexture = {
        let s = 64
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let grad = CGGradient(colorsSpace: space,
                                    colors: [SKColor.white.cgColor,
                                             SKColor(white: 1, alpha: 0).cgColor] as CFArray,
                                    locations: [0, 1])
        else { return SKTexture() }
        let c = CGPoint(x: s / 2, y: s / 2)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0,
                               endCenter: c, endRadius: CGFloat(s / 2), options: [])
        guard let img = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: img)
    }()

    init(spec: CharacterSpec) {
        body = spec.bodyColor.skColor
        accent = spec.accentColor.skColor
        outline = spec.bodyColor.darkened(0.28)
        current = Animator.idle(clock: 0)

        shadow.fillColor = SKColor(white: 0, alpha: 0.35); shadow.strokeColor = .clear
        shadow.zPosition = -1
        root.addChild(shadow)

        // Rim/impact light (behind the body).
        glow.texture = SkeletonRenderer.softGlow
        glow.color = accent; glow.colorBlendFactor = 1; glow.blendMode = .add
        glow.size = CGSize(width: 48, height: 48); glow.alpha = 0.16; glow.zPosition = -0.5
        root.addChild(glow)

        // Verlet "spirit ribbon" trailing the fighter.
        ribbonNode.strokeColor = accent; ribbonNode.lineWidth = 4
        ribbonNode.lineCap = .round; ribbonNode.lineJoin = .round
        ribbonNode.blendMode = .add; ribbonNode.alpha = 0.6; ribbonNode.zPosition = -0.4
        root.addChild(ribbonNode)
        ribbon = Array(repeating: .zero, count: ribbonCount); ribbonPrev = ribbon

        // Limb outline pass (dark, thick) then fill pass (color, thinner).
        func style(_ n: SKShapeNode, color: SKColor, width: CGFloat) {
            n.strokeColor = color; n.lineWidth = width; n.lineCap = .round; n.lineJoin = .round
        }
        for (o, f) in [(backLegO, backLeg), (backArmO, backArm)] {
            style(o, color: outline, width: 9); style(f, color: body, width: 5.5)
            root.addChild(o); root.addChild(f)
        }
        style(torsoOutline, color: outline, width: 19); style(torso, color: body, width: 14)
        root.addChild(torsoOutline); root.addChild(torso)
        for (o, f) in [(frontLegO, frontLeg), (frontArmO, frontArm)] {
            style(o, color: outline, width: 9); style(f, color: accent, width: 5.5)
            root.addChild(o); root.addChild(f)
        }
        head.fillColor = body; head.strokeColor = accent; head.lineWidth = 2.5
        root.addChild(head)
    }

    func update(for f: Fighter, clock: CGFloat, originX: CGFloat, groundY: CGFloat, flashHit: Bool) {
        current = current.lerp(to: Animator.pose(for: f, clock: clock), 0.4)
        let facing: CGFloat = f.facingRight ? 1 : -1
        let feetY = groundY + f.height
        func P(_ p: CGPoint) -> CGPoint { CGPoint(x: originX + p.x * facing, y: feetY + p.y) }

        let pelvis = P(current.pelvis), chest = P(current.chest)
        let seg = { (a: CGPoint, b: CGPoint) -> CGPath in
            let p = CGMutablePath(); p.move(to: a); p.addLine(to: b); return p
        }
        torsoOutline.path = seg(pelvis, chest); torso.path = seg(pelvis, chest)
        backArmO.path = seg(chest, P(current.backHand));  backArm.path = backArmO.path
        backLegO.path = seg(pelvis, P(current.backFoot)); backLeg.path = backLegO.path
        frontArmO.path = seg(chest, P(current.frontHand)); frontArm.path = frontArmO.path
        frontLegO.path = seg(pelvis, P(current.frontFoot)); frontLeg.path = frontLegO.path
        head.position = P(current.head)

        // Shadow shrinks with jump height.
        shadow.setScale(max(0.4, 1 - f.height / 120))
        shadow.position = CGPoint(x: originX, y: groundY + 1)

        let hit = flashHit || f.state == .hitStun || f.state == .launched
        root.alpha = f.isBlocking ? 0.78 : 1
        let fillBody = hit ? SKColor.white : body
        let fillAccent = hit ? SKColor.white : accent
        torso.strokeColor = fillBody
        backArm.strokeColor = fillBody; backLeg.strokeColor = fillBody
        frontArm.strokeColor = fillAccent; frontLeg.strokeColor = fillAccent
        head.fillColor = fillBody

        // Dynamic rim light: flares during attacks, blinds white on impact.
        let base: CGFloat = f.state == .active ? 0.85 : (f.state == .startup ? 0.45 : 0.16)
        glow.position = chest
        glow.alpha = hit ? 0.65 : base * (0.85 + 0.15 * sin(clock * 6))
        glow.color = hit ? .white : accent

        updateRibbon(anchor: CGPoint(x: chest.x - facing * 7, y: chest.y + 5), hit: hit)
    }

    /// Simple verlet integration — the ribbon flows behind the fighter with
    /// gravity + inertia and rigid segment constraints. Cloth physics, no art.
    private func updateRibbon(anchor: CGPoint, hit: Bool) {
        if !ribbonSeeded {
            for i in 0..<ribbonCount { ribbon[i] = anchor; ribbonPrev[i] = anchor }
            ribbonSeeded = true
        }
        ribbon[0] = anchor; ribbonPrev[0] = anchor
        for i in 1..<ribbonCount {
            let cur = ribbon[i]
            let vx = (cur.x - ribbonPrev[i].x) * 0.82
            let vy = (cur.y - ribbonPrev[i].y) * 0.82
            ribbonPrev[i] = cur
            ribbon[i] = CGPoint(x: cur.x + vx, y: cur.y + vy - 0.7)  // gravity
        }
        // Constraint passes keep segments a fixed length.
        for _ in 0..<2 {
            for i in 1..<ribbonCount {
                let dx = ribbon[i].x - ribbon[i - 1].x
                let dy = ribbon[i].y - ribbon[i - 1].y
                let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
                let k = (len - ribbonSeg) / len
                ribbon[i].x -= dx * k; ribbon[i].y -= dy * k
            }
        }
        let path = CGMutablePath()
        path.move(to: ribbon[0])
        for i in 1..<ribbonCount { path.addLine(to: ribbon[i]) }
        ribbonNode.path = path
        ribbonNode.strokeColor = hit ? .white : accent
    }
}
#endif
