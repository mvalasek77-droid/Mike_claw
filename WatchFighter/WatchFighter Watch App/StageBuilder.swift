#if os(watchOS)
import SpriteKit

extension RGBA {
    var skColor: SKColor { SKColor(red: r, green: g, blue: b, alpha: a) }
}

/// Turns a `StageSpec` into a layered SpriteKit node: a gradient sky, two
/// parallax silhouette layers driven by the stage motif, a ground strip, and a
/// soft accent glow. Built once per fight and parented behind the fighters.
enum StageBuilder {

    static func build(_ spec: StageSpec, size: CGSize) -> SKNode {
        let root = SKNode()
        root.zPosition = -10

        // Gradient sky.
        let sky = SKSpriteNode(texture: gradientTexture(top: spec.skyTop.skColor,
                                                        bottom: spec.skyBottom.skColor,
                                                        size: size))
        sky.anchorPoint = CGPoint(x: 0, y: 0)
        sky.position = .zero
        sky.zPosition = -10
        root.addChild(sky)

        // Accent glow band near the horizon.
        let glow = SKSpriteNode(color: spec.accent.skColor,
                                size: CGSize(width: size.width, height: 3))
        glow.anchorPoint = CGPoint(x: 0, y: 0)
        glow.position = CGPoint(x: 0, y: size.height * 0.42)
        glow.alpha = 0.5
        glow.zPosition = -7
        glow.blendMode = .add
        root.addChild(glow)

        // Parallax silhouettes.
        let far = silhouette(for: spec, size: size, depth: .far)
        far.zPosition = -9
        root.addChild(far)
        let mid = silhouette(for: spec, size: size, depth: .mid)
        mid.zPosition = -8
        root.addChild(mid)

        // Ground.
        let groundH = size.height * 0.42
        let ground = SKSpriteNode(color: spec.groundColor.skColor,
                                  size: CGSize(width: size.width, height: groundH))
        ground.anchorPoint = CGPoint(x: 0, y: 0)
        ground.position = .zero
        ground.zPosition = -6
        root.addChild(ground)

        // Ground line.
        let line = SKSpriteNode(color: spec.accent.skColor,
                                size: CGSize(width: size.width, height: 1.5))
        line.anchorPoint = CGPoint(x: 0, y: 0)
        line.position = CGPoint(x: 0, y: groundH)
        line.alpha = 0.6
        line.zPosition = -5
        root.addChild(line)

        return root
    }

    // MARK: - Parallax silhouette layers

    private enum Depth { case far, mid
        var shade: CGFloat { self == .far ? 1.0 : 1.0 }
        var baseY: CGFloat { self == .far ? 0.42 : 0.42 }
        var heightRange: ClosedRange<CGFloat> { self == .far ? 0.14...0.30 : 0.20...0.42 }
    }

    private static func silhouette(for spec: StageSpec, size: CGSize, depth: Depth) -> SKNode {
        let color = (depth == .far ? spec.farColor : spec.midColor).skColor
        let node = SKNode()
        let groundY = size.height * depth.baseY
        let path = CGMutablePath()

        switch spec.motif {
        case .city, .ruins, .throne:
            // Skyline of rectangles of varying height.
            var x: CGFloat = -8
            let step: CGFloat = depth == .far ? 16 : 24
            while x < size.width + 8 {
                let h = size.height * CGFloat.random(in: depth.heightRange)
                let w = step * CGFloat.random(in: 0.6...0.95)
                path.addRect(CGRect(x: x, y: groundY, width: w, height: h))
                x += step
            }

        case .volcano, .glacier, .temple:
            // Jagged peaks (triangles).
            var x: CGFloat = -10
            let step: CGFloat = depth == .far ? 26 : 40
            while x < size.width + 10 {
                let h = size.height * CGFloat.random(in: depth.heightRange)
                path.move(to: CGPoint(x: x, y: groundY))
                path.addLine(to: CGPoint(x: x + step / 2, y: groundY + h))
                path.addLine(to: CGPoint(x: x + step, y: groundY))
                path.closeSubpath()
                x += step
            }

        case .dojo:
            // Horizontal beams + uprights.
            for i in 0..<3 {
                let y = groundY + size.height * (0.12 + 0.10 * CGFloat(i))
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: 3))
            }
            var x: CGFloat = size.width * 0.15
            while x < size.width {
                path.addRect(CGRect(x: x, y: groundY, width: 4, height: size.height * 0.34))
                x += size.width * 0.35
            }

        case .ship:
            // A central mast with a triangular sail + a deck rail.
            let mastX = size.width * (depth == .far ? 0.7 : 0.4)
            let mastH = size.height * (depth == .far ? 0.34 : 0.46)
            path.addRect(CGRect(x: mastX, y: groundY, width: 5, height: mastH))
            path.move(to: CGPoint(x: mastX, y: groundY + mastH * 0.25))
            path.addLine(to: CGPoint(x: mastX - 46, y: groundY + mastH * 0.15))
            path.addLine(to: CGPoint(x: mastX, y: groundY + mastH * 0.85))
            path.closeSubpath()
            path.addRect(CGRect(x: 0, y: groundY + 6, width: size.width, height: 4))

        case .ring:
            // Boxing ring: three ropes + four corner posts.
            for i in 0..<3 {
                let y = groundY + 8 + CGFloat(i) * 9
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: 2))
            }
            for px in [CGFloat(6), size.width - 12] {
                path.addRect(CGRect(x: px, y: groundY, width: 6, height: 34))
            }
        }

        let shape = SKShapeNode(path: path)
        shape.fillColor = color
        shape.strokeColor = .clear
        node.addChild(shape)

        // Lava/ice glints for the elemental stages.
        if spec.motif == .volcano || spec.motif == .glacier {
            let glints = SKShapeNode()
            let gp = CGMutablePath()
            for _ in 0..<6 {
                let gx = CGFloat.random(in: 0...size.width)
                gp.addRect(CGRect(x: gx, y: groundY + CGFloat.random(in: 4...20),
                                  width: 2, height: 2))
            }
            glints.path = gp
            glints.fillColor = spec.accent.skColor
            glints.strokeColor = .clear
            glints.alpha = 0.7
            glints.blendMode = .add
            node.addChild(glints)
        }
        return node
    }

    // MARK: - Gradient texture

    private static func gradientTexture(top: SKColor, bottom: SKColor, size: CGSize) -> SKTexture {
        let w = max(2, Int(size.width)), h = max(2, Int(size.height))
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: space,
                                        colors: [bottom.cgColor, top.cgColor] as CFArray,
                                        locations: [0, 1])
        else { return SKTexture() }
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: 0, y: h),
                               options: [])
        guard let cg = ctx.makeImage() else { return SKTexture() }
        return SKTexture(cgImage: cg)
    }
}
#endif
