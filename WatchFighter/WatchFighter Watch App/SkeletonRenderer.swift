#if os(watchOS)
import SpriteKit

extension RGBA {
    // `skColor` is defined in StageBuilder.swift.
    /// A darkened version for outlines/shading.
    func darkened(_ k: CGFloat = 0.3) -> SKColor { SKColor(red: r * k, green: g * k, blue: b * k, alpha: 1) }
    /// A lightened/desaturated version for lit highlights.
    func lightened(_ k: CGFloat = 0.55) -> SKColor {
        SKColor(red: min(1, r + k), green: min(1, g + k), blue: min(1, b + k), alpha: 1)
    }
}

/// Anything that can draw a fighter. Lets `FightScene` use either the procedural
/// `SkeletonRenderer` or a `SpriteFighter` (when real art exists) behind one API.
protocol FighterRenderer: AnyObject {
    var root: SKNode { get }
    func update(for f: Fighter, clock: CGFloat, originX: CGFloat, groundY: CGFloat, flashHit: Bool)
}

/// Procedural "2.5D" fighter — the math-and-art technique:
/// each limb/torso is drawn as a **3-slice depth stack** — a dark back-extrusion
/// slice, the mid body, and a lit front highlight offset toward a fixed
/// screen-space light — which fakes volume and a rounded, lit look with zero art
/// or 3D. Body **proportions** vary by `Build` (broad / athletic / lithe), and a
/// verlet ribbon + dynamic rim light add motion and "pop". Driven entirely by the
/// pure `Animator`, so it stays deterministic + netplay-safe.
final class SkeletonRenderer: FighterRenderer {
    let root = SKNode()

    // Fixed screen-space light (upper-left). Back slice goes the other way.
    private let lightOff = CGPoint(x: -2.6, y: 2.2)
    private let depthOff = CGPoint(x: 2.4, y: -2.0)

    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 30, height: 7))
    private let glow = SKSpriteNode()
    private let ribbonNode = SKShapeNode()

    // Depth-stacked limbs: each is [back, mid, hi].
    private let torsoBack = SKShapeNode(), torso = SKShapeNode(), torsoHi = SKShapeNode()
    private let backArmB = SKShapeNode(), backArm = SKShapeNode()
    private let backLegB = SKShapeNode(), backLeg = SKShapeNode()
    private let frontLegB = SKShapeNode(), frontLeg = SKShapeNode(), frontLegHi = SKShapeNode()
    private let frontArmB = SKShapeNode(), frontArm = SKShapeNode(), frontArmHi = SKShapeNode()
    private let head = SKShapeNode(circleOfRadius: 6.5)
    private let headBack = SKShapeNode(circleOfRadius: 6.5)
    private let headSpec = SKShapeNode(circleOfRadius: 2.4)

    private var ribbon: [CGPoint] = [], ribbonPrev: [CGPoint] = []
    private var ribbonSeeded = false
    private let ribbonCount = 9, ribbonSeg: CGFloat = 5
    private var lastOriginX: CGFloat = .nan   // for walk-cycle detection
    private var walkPhase: CGFloat = 0

    private var current: Pose
    private let body: SKColor, accent: SKColor, dark: SKColor, hi: SKColor
    private let widthScale: CGFloat, limbScale: CGFloat, headScale: CGFloat

    /// Soft radial-gradient sprite generated once with Core Graphics — the rim/
    /// impact light. Pure code, no art file.
    static let softGlow: SKTexture = {
        let s = 64
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let grad = CGGradient(colorsSpace: space,
                                    colors: [SKColor.white.cgColor, SKColor(white: 1, alpha: 0).cgColor] as CFArray,
                                    locations: [0, 1])
        else { return SKTexture() }
        let c = CGPoint(x: s / 2, y: s / 2)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(s / 2), options: [])
        guard let img = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: img)
    }()

    init(spec: CharacterSpec) {
        body = spec.bodyColor.skColor
        accent = spec.accentColor.skColor
        dark = spec.bodyColor.darkened(0.18)
        hi = spec.bodyColor.lightened(0.5)
        widthScale = spec.build.widthScale
        limbScale = spec.build.limbScale
        headScale = spec.build.headScale
        current = Animator.idle(clock: 0)

        shadow.fillColor = SKColor(white: 0, alpha: 0.35); shadow.strokeColor = .clear
        shadow.zPosition = -1; root.addChild(shadow)

        glow.texture = SkeletonRenderer.softGlow
        glow.color = accent; glow.colorBlendFactor = 1; glow.blendMode = .add
        glow.size = CGSize(width: 50, height: 50); glow.alpha = 0.16; glow.zPosition = -0.5
        root.addChild(glow)

        ribbonNode.strokeColor = accent; ribbonNode.lineWidth = 4
        ribbonNode.lineCap = .round; ribbonNode.lineJoin = .round
        ribbonNode.blendMode = .add; ribbonNode.alpha = 0.6; ribbonNode.zPosition = -0.4
        root.addChild(ribbonNode)
        ribbon = Array(repeating: .zero, count: ribbonCount); ribbonPrev = ribbon

        func style(_ n: SKShapeNode, _ color: SKColor, _ width: CGFloat, alpha: CGFloat = 1) {
            n.strokeColor = color; n.lineWidth = width * limbScale
            n.lineCap = .round; n.lineJoin = .round; n.alpha = alpha
        }
        let lw: CGFloat = 6                       // base limb width
        // Add order = back to front: depth stack reads as volume.
        for n in [headBack] { n.fillColor = dark; n.strokeColor = .clear; n.setScale(headScale); root.addChild(n) }
        style(backLegB, dark, 10); style(backLeg, body, lw)
        style(backArmB, dark, 10); style(backArm, body, lw)
        root.addChild(backLegB); root.addChild(backLeg)
        root.addChild(backArmB); root.addChild(backArm)
        style(torsoBack, dark, 21); style(torso, body, 15); style(torsoHi, hi, 6, alpha: 0.9)
        root.addChild(torsoBack); root.addChild(torso); root.addChild(torsoHi)
        style(frontLegB, dark, 10); style(frontLeg, accent, lw); style(frontLegHi, hi, 3.5, alpha: 0.85)
        style(frontArmB, dark, 10); style(frontArm, accent, lw); style(frontArmHi, hi, 3.5, alpha: 0.85)
        root.addChild(frontLegB); root.addChild(frontLeg); root.addChild(frontLegHi)
        root.addChild(frontArmB); root.addChild(frontArm); root.addChild(frontArmHi)
        head.fillColor = body; head.strokeColor = accent; head.lineWidth = 2.5
        head.setScale(headScale); root.addChild(head)
        headSpec.fillColor = .white; headSpec.strokeColor = .clear
        headSpec.blendMode = .add; headSpec.alpha = 0.55; root.addChild(headSpec)
    }

    func update(for f: Fighter, clock: CGFloat, originX: CGFloat, groundY: CGFloat, flashHit: Bool) {
        // Walk cycle: if the fighter is moving on the ground in neutral, play the
        // walk pose instead of the idle bob (fixes "sliding while standing").
        if lastOriginX.isNaN { lastOriginX = originX }
        let dx = originX - lastOriginX
        lastOriginX = originX
        var target = Animator.pose(for: f, clock: clock)
        if f.state == .idle && !f.airborne && !f.isBlocking && abs(dx) > 0.2 {
            walkPhase += abs(dx) * 0.22
            target = Animator.walk(phase: walkPhase)
        }
        current = current.lerp(to: target, 0.4)
        let facing: CGFloat = f.facingRight ? 1 : -1
        let feetY = groundY + f.height
        func P(_ p: CGPoint) -> CGPoint {
            CGPoint(x: originX + p.x * facing * widthScale, y: feetY + p.y)
        }
        func seg(_ a: CGPoint, _ b: CGPoint, _ o: CGPoint = .zero) -> CGPath {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: a.x + o.x, y: a.y + o.y))
            p.addLine(to: CGPoint(x: b.x + o.x, y: b.y + o.y))
            return p
        }

        let pelvis = P(current.pelvis), chest = P(current.chest), headP = P(current.head)
        let fH = P(current.frontHand), bH = P(current.backHand)
        let fF = P(current.frontFoot), bF = P(current.backFoot)

        torsoBack.path = seg(pelvis, chest, depthOff)
        torso.path = seg(pelvis, chest)
        torsoHi.path = seg(pelvis, chest, lightOff)
        backArmB.path = seg(chest, bH, depthOff); backArm.path = seg(chest, bH)
        backLegB.path = seg(pelvis, bF, depthOff); backLeg.path = seg(pelvis, bF)
        frontArmB.path = seg(chest, fH, depthOff); frontArm.path = seg(chest, fH); frontArmHi.path = seg(chest, fH, lightOff)
        frontLegB.path = seg(pelvis, fF, depthOff); frontLeg.path = seg(pelvis, fF); frontLegHi.path = seg(pelvis, fF, lightOff)
        head.position = headP
        headBack.position = CGPoint(x: headP.x + depthOff.x, y: headP.y + depthOff.y)
        headSpec.position = CGPoint(x: headP.x + lightOff.x, y: headP.y + lightOff.y)

        shadow.setScale(max(0.4, 1 - f.height / 120))
        shadow.position = CGPoint(x: originX, y: groundY + 1)

        let hit = flashHit || f.state == .hitStun || f.state == .launched
        root.alpha = f.isBlocking ? 0.8 : 1
        let fillBody = hit ? SKColor.white : body
        let fillAccent = hit ? SKColor.white : accent
        torso.strokeColor = fillBody
        backArm.strokeColor = fillBody; backLeg.strokeColor = fillBody
        frontArm.strokeColor = fillAccent; frontLeg.strokeColor = fillAccent
        head.fillColor = fillBody

        let base: CGFloat = f.state == .active ? 0.9 : (f.state == .startup ? 0.45 : 0.16)
        glow.position = chest
        glow.alpha = hit ? 0.7 : base * (0.85 + 0.15 * sin(clock * 6))
        glow.color = hit ? .white : accent

        updateRibbon(anchor: CGPoint(x: chest.x - facing * 7, y: chest.y + 5), hit: hit)
    }

    /// Verlet integration — the ribbon flows with gravity + inertia and rigid
    /// segment constraints. Cloth physics, no art.
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
            ribbon[i] = CGPoint(x: cur.x + vx, y: cur.y + vy - 0.7)
        }
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
