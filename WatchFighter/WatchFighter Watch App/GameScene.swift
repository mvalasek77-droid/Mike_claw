#if os(watchOS)
import SpriteKit

/// SpriteKit scene that owns the fixed-timestep combat loop, draws the two
/// fighters + HUD, routes touch gestures into `Intent`s, drives the CPU, and
/// fires haptics. Rendering is deliberately minimal (silhouettes + bars) so it
/// stays legible at watch size and inside the 16ms frame budget.
final class GameScene: SKScene {

    // Engine
    private var combat = CombatSystem(playerSpec: .volt, opponentSpec: .bastion)
    private var ai = AIController(difficulty: .normal)
    private var pendingCrown: CGFloat = 0

    // Fixed-timestep accumulator
    private var lastTime: TimeInterval = 0
    private var accumulator: TimeInterval = 0
    private let step = 1.0 / CombatSystem.tickRate

    // Nodes
    private let playerNode = SKShapeNode(rectOf: CGSize(width: 26, height: 60), cornerRadius: 4)
    private let oppNode = SKShapeNode(rectOf: CGSize(width: 26, height: 60), cornerRadius: 4)
    private let playerHP = SKShapeNode()
    private let oppHP = SKShapeNode()
    private let playerMeter = SKShapeNode()
    private let telegraph = SKLabelNode(text: "!")
    private let banner = SKLabelNode(text: "")

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1)
        scaleMode = .resizeFill

        playerNode.fillColor = SKColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 1)
        playerNode.strokeColor = .white
        oppNode.fillColor = SKColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1)
        oppNode.strokeColor = .white
        [playerNode, oppNode].forEach { $0.zPosition = 1; addChild($0) }

        [playerHP, oppHP, playerMeter].forEach { $0.zPosition = 2; addChild($0) }

        telegraph.fontName = "Menlo-Bold"
        telegraph.fontColor = .yellow
        telegraph.fontSize = 28
        telegraph.alpha = 0
        telegraph.zPosition = 3
        addChild(telegraph)

        banner.fontName = "Menlo-Bold"
        banner.fontSize = 20
        banner.fontColor = .white
        banner.alpha = 0
        banner.zPosition = 4
        addChild(banner)
    }

    // MARK: - Crown input (forwarded from SwiftUI)

    /// Called by the hosting SwiftUI view with the latest Crown delta.
    func feedCrown(delta: CGFloat) { pendingCrown += delta }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        if lastTime == 0 { lastTime = currentTime }
        accumulator += min(0.25, currentTime - lastTime)  // clamp huge gaps
        lastTime = currentTime

        // Flush accumulated Crown rotation as a single charge intent per frame.
        if let crown = InputController.crownIntent(delta: pendingCrown) {
            dispatch(combat.apply(crown, from: .player))
            pendingCrown = 0
        }

        while accumulator >= step {
            accumulator -= step
            stepOnce()
        }
        render()
    }

    private func stepOnce() {
        guard !combat.isOver else { return }
        if let move = ai.decide(opponent: combat.opponent, player: combat.player) {
            dispatch(combat.apply(move, from: .opponent))
        }
        dispatch(combat.tick())
    }

    private func dispatch(_ events: [CombatEvent]) {
        for e in events {
            Haptics.play(for: e, viewer: .player)
            if case .heavyWindup(let s) = e, s == .opponent { flashTelegraph() }
            if case .roundOver(let w) = e { showBanner(w) }
        }
    }

    // MARK: - Rendering

    private func render() {
        let groundY = size.height * 0.42
        playerNode.position = CGPoint(x: laneToScreenX(combat.player.position) + lunge(combat.player), y: groundY)
        oppNode.position = CGPoint(x: laneToScreenX(combat.opponent.position) - lunge(combat.opponent), y: groundY)

        playerNode.alpha = combat.player.isBlocking ? 0.5 : 1
        oppNode.alpha = combat.opponent.isBlocking ? 0.5 : 1
        flash(playerNode, if: combat.player.state == .hitStun)
        flash(oppNode, if: combat.opponent.state == .hitStun)

        drawBar(playerHP, frac: combat.player.healthFraction,
                rect: CGRect(x: 6, y: size.height - 14, width: size.width/2 - 10, height: 8),
                color: .green)
        drawBar(oppHP, frac: combat.opponent.healthFraction,
                rect: CGRect(x: size.width/2 + 4, y: size.height - 14, width: size.width/2 - 10, height: 8),
                color: .red, rightAligned: true)
        drawBar(playerMeter, frac: CGFloat(combat.player.meter)/100,
                rect: CGRect(x: 6, y: 6, width: size.width - 12, height: 5),
                color: combat.player.meterFull ? .yellow : .cyan)

        telegraph.position = CGPoint(x: oppNode.position.x, y: groundY + 50)
    }

    private func lunge(_ f: Fighter) -> CGFloat {
        f.state == .active ? (f.currentMove?.reach ?? 0) * 0.4 * (f.facingRight ? 1 : -1) : 0
    }

    private func laneToScreenX(_ x: CGFloat) -> CGFloat {
        let t = (x - CombatSystem.laneMin) / (CombatSystem.laneMax - CombatSystem.laneMin)
        return 20 + t * (size.width - 40)
    }

    private func drawBar(_ node: SKShapeNode, frac: CGFloat, rect: CGRect,
                         color: SKColor, rightAligned: Bool = false) {
        let w = max(0, rect.width * frac)
        let x = rightAligned ? rect.maxX - w : rect.minX
        node.path = CGPath(rect: CGRect(x: x, y: rect.minY, width: w, height: rect.height), transform: nil)
        node.fillColor = color
        node.strokeColor = .clear
    }

    private func flash(_ node: SKShapeNode, if condition: Bool) {
        node.strokeColor = condition ? .white : .clear
        node.lineWidth = condition ? 3 : 1
    }

    private func flashTelegraph() {
        telegraph.removeAllActions()
        telegraph.alpha = 1
        telegraph.run(.fadeOut(withDuration: 0.35))
    }

    private func showBanner(_ winner: Side?) {
        banner.text = winner == .player ? "K.O. — YOU WIN" : winner == .opponent ? "DEFEATED" : "DRAW"
        banner.position = CGPoint(x: size.width/2, y: size.height/2)
        banner.run(.fadeIn(withDuration: 0.3))
    }

    // MARK: - Gesture input (forwarded from SwiftUI; watchOS has no UITouch)

    /// Finger down: provisionally start blocking. A quick release reclassifies
    /// into a tap/swipe attack; a sustained hold stays a block.
    func touchDown() {
        dispatch(combat.apply(.beginBlock, from: .player))
    }

    /// Finger up. `translation` and `startLocation` arrive in SwiftUI space
    /// (y-down, origin top-left); we convert to scene space (y-up) here.
    func touchUp(translation: CGSize, startLocation: CGPoint, held: TimeInterval) {
        dispatch(combat.apply(.endBlock, from: .player))

        let dx = translation.width
        let dy = -translation.height            // SwiftUI y-down -> scene y-up

        if hypot(dx, dy) > 24 {                  // swipe
            if let intent = InputController.swipeIntent(dx: dx, dy: dy) {
                dispatch(combat.apply(intent, from: .player))
            }
        } else if held < 0.4 {                   // quick tap (longer hold = block)
            let p = CGPoint(x: startLocation.x, y: size.height - startLocation.y)
            // A tap on the right edge with meter ready throws the special.
            if combat.player.meter >= CombatSystem.chargeToFire && p.x > size.width * 0.66 {
                dispatch(combat.apply(.special, from: .player))
            } else {
                dispatch(combat.apply(InputController.tapIntent(at: p, in: size), from: .player))
            }
        }
    }
}
#endif
