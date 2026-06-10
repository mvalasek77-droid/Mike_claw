#if os(watchOS)
import SpriteKit

/// Texture-atlas fighter — the "real graphics" path. Drops in automatically the
/// moment a Sprite Atlas named `<id>_atlas` ships in `Assets.xcassets`, with
/// frames named `<id>_<anim>_<n>` (e.g. `volt_idle_0`, `volt_attack_2`). See
/// `ASSET_SPEC.md`. Until art exists, `FightScene` falls back to the procedural
/// `SkeletonRenderer`, so the game always runs.
///
/// Animation is driven by the same pure combat state as the skeleton, so it is
/// deterministic and netplay-safe.
final class SpriteFighter: FighterRenderer {
    let root = SKNode()

    private let sprite = SKSpriteNode()
    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 32, height: 7))
    private let id: String
    private let atlas: SKTextureAtlas
    private var cache: [String: [SKTexture]] = [:]
    private var halfHeight: CGFloat = 30
    private let fps: CGFloat = 12

    init(spec: CharacterSpec, atlas: SKTextureAtlas) {
        self.id = spec.id
        self.atlas = atlas

        shadow.fillColor = SKColor(white: 0, alpha: 0.35); shadow.strokeColor = .clear
        shadow.zPosition = -1
        root.addChild(shadow)

        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        sprite.color = .white
        if let first = textures(for: "idle").first {
            sprite.texture = first
            sprite.size = first.size()
            halfHeight = first.size().height / 2
        }
        root.addChild(sprite)
    }

    func update(for f: Fighter, clock: CGFloat, originX: CGFloat, groundY: CGFloat, flashHit: Bool) {
        let name = animName(for: f)
        let frames = textures(for: name)
        if !frames.isEmpty {
            let idx = Int(clock * fps) % frames.count
            sprite.texture = frames[idx]
        }
        sprite.xScale = f.facingRight ? 1 : -1
        sprite.position = CGPoint(x: originX, y: groundY + f.height + halfHeight)

        shadow.setScale(max(0.4, 1 - f.height / 120))
        shadow.position = CGPoint(x: originX, y: groundY + 1)

        // White flash on impact via the sprite's built-in color blend.
        let hit = flashHit || f.state == .hitStun || f.state == .launched
        sprite.colorBlendFactor = hit ? 0.7 : 0
        root.alpha = f.isBlocking ? 0.85 : 1
    }

    private func animName(for f: Fighter) -> String {
        if f.isBlocking && f.state == .idle { return "block" }
        switch f.state {
        case .idle:                         return f.airborne ? "jump" : "idle"
        case .startup, .active, .recovery:  return "attack"
        case .blockStun, .parry:            return "block"
        case .hitStun, .dizzy:              return "hurt"
        case .launched:                     return "jump"
        case .knockdown, .wakeup:           return "down"
        }
    }

    /// Frames for an animation, falling back to `idle` if a set is missing.
    private func textures(for name: String) -> [SKTexture] {
        if let cached = cache[name] { return cached }
        let prefix = "\(id)_\(name)_"
        let frames = atlas.textureNames
            .filter { $0.hasPrefix(prefix) }
            .sorted()
            .map { atlas.textureNamed($0) }
        let result = frames.isEmpty && name != "idle" ? textures(for: "idle") : frames
        cache[name] = result
        return result
    }
}
#endif
