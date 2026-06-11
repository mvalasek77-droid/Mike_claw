#if os(watchOS)
import SpriteKit

extension RGBA {
    // `skColor` is defined in StageBuilder.swift.
    func darkened(_ k: CGFloat = 0.3) -> SKColor { SKColor(red: r * k, green: g * k, blue: b * k, alpha: 1) }
    func lightened(_ k: CGFloat = 0.5) -> SKColor {
        SKColor(red: min(1, r + k), green: min(1, g + k), blue: min(1, b + k), alpha: 1)
    }
}

/// Anything that can draw a fighter (procedural or sprite-art) behind one API.
protocol FighterRenderer: AnyObject {
    var root: SKNode { get }
    func update(for f: Fighter, clock: CGFloat, originX: CGFloat, groundY: CGFloat, flashHit: Bool)
}

/// Procedurally-skinned human fighter — the "arcade character" technique with no
/// art assets: limbs/torso are **shaded capsule muscles** (a code-generated
/// gradient capsule texture, tinted per character so it reads as a lit, rounded
/// 3D form), topped with a **composed face** (skin tone + hair + eyes). Skin vs.
/// outfit vs. accent give it a real human read; `Build` sets the proportions.
/// Driven by the pure `Animator`, so it stays deterministic + netplay-safe.
final class SkeletonRenderer: FighterRenderer {
    let root = SKNode()

    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 30, height: 7))
    private let glow = SKSpriteNode()
    private let ribbonNode = SKShapeNode()
    private var ribbon: [CGPoint] = [], ribbonPrev: [CGPoint] = []
    private var ribbonSeeded = false
    private let ribbonCount = 9, ribbonSeg: CGFloat = 5
    private var lastOriginX: CGFloat = .nan, walkPhase: CGFloat = 0

    // Shaded capsule limbs.
    private let torsoS = SKSpriteNode(texture: SkeletonRenderer.capsuleTex)
    private let backArmS = SKSpriteNode(texture: SkeletonRenderer.capsuleTex)
    private let backLegS = SKSpriteNode(texture: SkeletonRenderer.capsuleTex)
    private let frontArmS = SKSpriteNode(texture: SkeletonRenderer.capsuleTex)
    private let frontLegS = SKSpriteNode(texture: SkeletonRenderer.capsuleTex)

    // Hands / feet.
    private let frontFist = SKShapeNode(circleOfRadius: 3.0)
    private let backFist = SKShapeNode(circleOfRadius: 2.6)
    private let frontFootN = SKShapeNode(circleOfRadius: 3.2)
    private let backFootN = SKShapeNode(circleOfRadius: 2.8)

    // Face.
    private let hairCap: SKShapeNode
    private let skinHead: SKShapeNode
    private let eyeL = SKShapeNode(circleOfRadius: 0.95)
    private let eyeR = SKShapeNode(circleOfRadius: 0.95)

    private var current: Pose
    private let outfit: SKColor, outfitDark: SKColor, accent: SKColor
    private let skin: SKColor, skinDark: SKColor
    private let widthScale: CGFloat, limbScale: CGFloat, headR: CGFloat

    /// Code-generated vertical capsule with a left→right shading gradient. When
    /// tinted (colorBlendFactor) it reads as a lit, rounded muscle. No art file.
    static let capsuleTex: SKTexture = {
        let w = 28, h = 80
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return SKTexture() }
        let rect = CGRect(x: 1, y: 1, width: w - 2, height: h - 2)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: CGFloat(w - 2) / 2,
                           cornerHeight: CGFloat(w - 2) / 2, transform: nil))
        ctx.clip()
        guard let grad = CGGradient(colorsSpace: space,
                                    colors: [SKColor(white: 1, alpha: 1).cgColor,
                                             SKColor(white: 0.42, alpha: 1).cgColor] as CFArray,
                                    locations: [0, 1]) else { return SKTexture() }
        ctx.drawLinearGradient(grad, start: CGPoint(x: 2, y: 0),
                               end: CGPoint(x: CGFloat(w - 2), y: 0), options: [])
        guard let img = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: img)
    }()

    /// Soft radial glow for the rim/impact light.
    static let softGlow: SKTexture = {
        let s = 64
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let grad = CGGradient(colorsSpace: space,
                                    colors: [SKColor.white.cgColor, SKColor(white: 1, alpha: 0).cgColor] as CFArray,
                                    locations: [0, 1]) else { return SKTexture() }
        let c = CGPoint(x: s / 2, y: s / 2)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(s / 2), options: [])
        guard let img = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: img)
    }()

    init(spec: CharacterSpec) {
        outfit = spec.bodyColor.skColor
        outfitDark = spec.bodyColor.darkened(0.6)
        accent = spec.accentColor.skColor
        skin = spec.skin.skColor
        skinDark = spec.skin.darkened(0.72)
        widthScale = spec.build.widthScale
        limbScale = spec.build.limbScale
        headR = 6.6 * spec.build.headScale
        current = Animator.idle(clock: 0)
        skinHead = SKShapeNode(circleOfRadius: headR)
        hairCap = SKShapeNode(ellipseOf: CGSize(width: headR * 2.1, height: headR * 1.35))

        shadow.fillColor = SKColor(white: 0, alpha: 0.35); shadow.strokeColor = .clear
        shadow.zPosition = -1; root.addChild(shadow)

        glow.texture = SkeletonRenderer.softGlow
        glow.color = accent; glow.colorBlendFactor = 1; glow.blendMode = .add
        glow.size = CGSize(width: 50, height: 50); glow.alpha = 0.16; glow.zPosition = -0.5
        root.addChild(glow)

        ribbonNode.strokeColor = accent; ribbonNode.lineWidth = 4
        ribbonNode.lineCap = .round; ribbonNode.lineJoin = .round
        ribbonNode.blendMode = .add; ribbonNode.alpha = 0.55; ribbonNode.zPosition = -0.4
        root.addChild(ribbonNode)
        ribbon = Array(repeating: .zero, count: ribbonCount); ribbonPrev = ribbon

        // Back limbs (darker), torso, front limbs (lit) — depth read.
        tint(backArmS, skinDark); tint(backLegS, outfitDark)
        root.addChild(backArmS); root.addChild(backLegS)
        backFist.fillColor = skinDark; backFootN.fillColor = outfitDark
        for n in [backFist, backFootN] { n.strokeColor = .clear; root.addChild(n) }
        tint(torsoS, outfit); root.addChild(torsoS)
        tint(frontLegS, outfit); tint(frontArmS, skin)
        root.addChild(frontLegS); root.addChild(frontArmS)
        frontFist.fillColor = skin; frontFootN.fillColor = outfit
        for n in [frontFist, frontFootN] { n.strokeColor = .clear; root.addChild(n) }

        // Face.
        hairCap.fillColor = accent; hairCap.strokeColor = .clear; root.addChild(hairCap)
        skinHead.fillColor = skin; skinHead.strokeColor = spec.skin.darkened(0.55); skinHead.lineWidth = 1
        root.addChild(skinHead)
        eyeL.fillColor = .black; eyeR.fillColor = .black
        eyeL.strokeColor = .clear; eyeR.strokeColor = .clear
        root.addChild(eyeL); root.addChild(eyeR)
    }

    private func tint(_ s: SKSpriteNode, _ color: SKColor) { s.color = color; s.colorBlendFactor = 0.82 }

    /// Orient a capsule sprite to span bone a→b at the given thickness.
    private func bone(_ s: SKSpriteNode, _ a: CGPoint, _ b: CGPoint, _ width: CGFloat) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(1, (dx * dx + dy * dy).squareRoot())
        s.position = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        s.zRotation = atan2(dy, dx) - .pi / 2
        s.size = CGSize(width: width, height: len + width * 0.5)
    }

    func update(for f: Fighter, clock: CGFloat, originX: CGFloat, groundY: CGFloat, flashHit: Bool) {
        if lastOriginX.isNaN { lastOriginX = originX }
        let dx0 = originX - lastOriginX
        lastOriginX = originX
        var target = Animator.pose(for: f, clock: clock)
        if f.state == .idle && !f.airborne && !f.isBlocking && abs(dx0) > 0.2 {
            walkPhase += abs(dx0) * 0.22
            target = Animator.walk(phase: walkPhase)
        }
        current = current.lerp(to: target, 0.4)

        let facing: CGFloat = f.facingRight ? 1 : -1
        let feetY = groundY + f.height
        func P(_ p: CGPoint) -> CGPoint { CGPoint(x: originX + p.x * facing * widthScale, y: feetY + p.y) }

        let pelvis = P(current.pelvis), chest = P(current.chest), headP = P(current.head)
        let fH = P(current.frontHand), bH = P(current.backHand)
        let fF = P(current.frontFoot), bF = P(current.backFoot)

        bone(torsoS, pelvis, chest, 13 * widthScale)
        bone(backArmS, chest, bH, 6 * limbScale)
        bone(backLegS, pelvis, bF, 7 * limbScale)
        bone(frontArmS, chest, fH, 6.5 * limbScale)
        bone(frontLegS, pelvis, fF, 7.5 * limbScale)
        frontFist.position = fH; backFist.position = bH
        frontFootN.position = fF; backFootN.position = bF

        skinHead.position = headP
        hairCap.position = CGPoint(x: headP.x - facing * 0.6, y: headP.y + headR * 0.55)
        eyeL.position = CGPoint(x: headP.x + facing * 1.4, y: headP.y + 0.7)
        eyeR.position = CGPoint(x: headP.x + facing * 3.2, y: headP.y + 0.7)

        shadow.setScale(max(0.4, 1 - f.height / 120))
        shadow.position = CGPoint(x: originX, y: groundY + 1)

        let hit = flashHit || f.state == .hitStun || f.state == .launched
        root.alpha = f.isBlocking ? 0.82 : 1
        torsoS.color = hit ? .white : outfit
        backArmS.color = hit ? .white : skinDark
        backLegS.color = hit ? .white : outfitDark
        frontArmS.color = hit ? .white : skin
        frontLegS.color = hit ? .white : outfit
        skinHead.fillColor = hit ? .white : skin
        frontFist.fillColor = hit ? .white : skin

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
