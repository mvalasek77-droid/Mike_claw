#if os(watchOS)
import SpriteKit

/// Runs one best-of-three match with full fighting-game presentation:
/// "ROUND n / FIGHT! / K.O." announcer beats, parallax stage, health bars with
/// round pips, super meter, live combo counter, projectiles, and haptics.
/// Reports the match winner via `onResult` so the story flow can advance.
final class FightScene: SKScene {

    // Match configuration
    private let stageSpec: StageSpec
    private var flow: MatchFlow
    private var ai: AIController
    private let onResult: (Side) -> Void
    private var resultReported = false

    // Presentation phases
    private enum Phase { case announceRound, announceFight, fighting, roundResult, matchResult }
    private var phase: Phase = .announceRound
    private var phaseClock: TimeInterval = 0

    // Loop bookkeeping
    private var pendingCrown: CGFloat = 0
    private var lastTime: TimeInterval = 0
    private var accumulator: TimeInterval = 0
    private let step = 1.0 / CombatSystem.tickRate

    // Nodes
    private let playerNode = SKShapeNode(rectOf: CGSize(width: 24, height: 58), cornerRadius: 4)
    private let oppNode = SKShapeNode(rectOf: CGSize(width: 24, height: 58), cornerRadius: 4)
    private let playerHP = SKShapeNode()
    private let oppHP = SKShapeNode()
    private let playerHPBack = SKShapeNode()
    private let oppHPBack = SKShapeNode()
    private let playerMeter = SKShapeNode()
    private let projectileLayer = SKNode()
    private var pipNodes: [SKShapeNode] = []
    private let comboLabel = SKLabelNode(text: "")
    private let announcer = SKLabelNode(text: "")
    private let timerLabel = SKLabelNode(text: "")
    private let nameLabelP = SKLabelNode(text: "")
    private let nameLabelO = SKLabelNode(text: "")
    private let telegraph = SKLabelNode(text: "!")

    init(playerSpec: CharacterSpec, opponentSpec: CharacterSpec,
         stage: StageSpec, difficulty: AIController.Difficulty = .normal,
         onResult: @escaping (Side) -> Void) {
        self.stageSpec = stage
        self.flow = MatchFlow(playerSpec: playerSpec, opponentSpec: opponentSpec)
        self.ai = AIController(difficulty: difficulty)
        self.onResult = onResult
        super.init(size: CGSize(width: 200, height: 240))
        scaleMode = .resizeFill
    }
    required init?(coder: NSCoder) { fatalError("use init(playerSpec:…)") }

    override func didMove(to view: SKView) {
        buildStage()
        buildFighters()
        buildHUD()
        beginPhase(.announceRound)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard isNodeTreeReady else { return }
        rebuildStage()
        layoutHUD()
    }
    private var isNodeTreeReady = false

    // MARK: - Build

    private func buildStage() {
        let bg = StageBuilder.build(stageSpec, size: size)
        bg.name = "stage"
        addChild(bg)
        isNodeTreeReady = true
    }
    private func rebuildStage() {
        childNode(withName: "stage")?.removeFromParent()
        buildStage()
    }

    private func buildFighters() {
        configureBody(playerNode, flow.playerSpec)
        configureBody(oppNode, flow.opponentSpec)
        [playerNode, oppNode].forEach { $0.zPosition = 1; addChild($0) }
        projectileLayer.zPosition = 2
        addChild(projectileLayer)
    }
    private func configureBody(_ node: SKShapeNode, _ spec: CharacterSpec) {
        node.fillColor = spec.bodyColor.skColor
        node.strokeColor = spec.accentColor.skColor
        node.lineWidth = 2
    }

    private func buildHUD() {
        [playerHPBack, oppHPBack, playerHP, oppHP, playerMeter].forEach {
            $0.zPosition = 5; addChild($0)
        }
        styleLabel(nameLabelP, size: 9); nameLabelP.text = flow.playerSpec.name
        styleLabel(nameLabelO, size: 9); nameLabelO.text = flow.opponentSpec.name
        styleLabel(timerLabel, size: 12)
        styleLabel(comboLabel, size: 13); comboLabel.fontColor = .yellow; comboLabel.alpha = 0
        styleLabel(announcer, size: 22); announcer.alpha = 0
        styleLabel(telegraph, size: 24); telegraph.fontColor = .yellow; telegraph.alpha = 0
        [nameLabelP, nameLabelO, timerLabel, comboLabel, announcer, telegraph].forEach {
            $0.zPosition = 6; addChild($0)
        }
        // Round pips (best-of-3 -> 2 to win, show 2 per side).
        for _ in 0..<4 {
            let pip = SKShapeNode(circleOfRadius: 2.5)
            pip.fillColor = .darkGray; pip.strokeColor = .clear; pip.zPosition = 6
            pipNodes.append(pip); addChild(pip)
        }
        layoutHUD()
    }
    private func styleLabel(_ l: SKLabelNode, size: CGFloat) {
        l.fontName = "Menlo-Bold"; l.fontSize = size; l.fontColor = .white
        l.verticalAlignmentMode = .center; l.horizontalAlignmentMode = .center
    }

    private func layoutHUD() {
        let top = size.height - 10
        playerHPBack.path = barPath(x: 6, y: top, w: size.width/2 - 12)
        oppHPBack.path = barPath(x: size.width/2 + 6, y: top, w: size.width/2 - 12)
        [playerHPBack, oppHPBack].forEach { $0.fillColor = SKColor(white: 0.15, alpha: 1); $0.strokeColor = .clear }
        nameLabelP.position = CGPoint(x: 6, y: top - 12); nameLabelP.horizontalAlignmentMode = .left
        nameLabelO.position = CGPoint(x: size.width - 6, y: top - 12); nameLabelO.horizontalAlignmentMode = .right
        timerLabel.position = CGPoint(x: size.width/2, y: top - 2)
        announcer.position = CGPoint(x: size.width/2, y: size.height * 0.62)
        comboLabel.position = CGPoint(x: size.width * 0.28, y: size.height * 0.55)
        for (i, pip) in pipNodes.enumerated() {
            let side = i < 2 ? CGFloat(1) : -1
            let idx = CGFloat(i % 2)
            let x = side > 0 ? 8 + idx * 9 : size.width - 8 - idx * 9
            pip.position = CGPoint(x: x, y: top - 22)
        }
    }
    private func barPath(x: CGFloat, y: CGFloat, w: CGFloat) -> CGPath {
        CGPath(rect: CGRect(x: x, y: y, width: max(0, w), height: 7), transform: nil)
    }

    // MARK: - Crown

    func feedCrown(delta: CGFloat) { pendingCrown += delta }

    // MARK: - Phase machine

    private func beginPhase(_ p: Phase) {
        phase = p; phaseClock = 0
        switch p {
        case .announceRound:
            showAnnouncer("ROUND \(flow.currentRound)", color: .white)
        case .announceFight:
            showAnnouncer("FIGHT!", color: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
        case .fighting:
            accumulator = 0
            announcer.run(.fadeOut(withDuration: 0.2))
        case .roundResult, .matchResult:
            break
        }
    }

    private func showAnnouncer(_ text: String, color: SKColor) {
        announcer.text = text; announcer.fontColor = color
        announcer.setScale(1.6); announcer.alpha = 0
        announcer.run(.group([.fadeIn(withDuration: 0.15), .scale(to: 1.0, duration: 0.25)]))
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        if lastTime == 0 { lastTime = currentTime }
        let dt = min(0.25, currentTime - lastTime)
        lastTime = currentTime
        phaseClock += dt

        switch phase {
        case .announceRound:
            if phaseClock > 1.1 { beginPhase(.announceFight) }
        case .announceFight:
            if phaseClock > 0.7 { beginPhase(.fighting) }
        case .fighting:
            runCombat(dt: dt)
        case .roundResult:
            if phaseClock > 1.5 { afterRoundResult() }
        case .matchResult:
            if phaseClock > 1.6 && !resultReported {
                resultReported = true
                onResult(flow.matchWinner ?? .opponent)
            }
        }
        render()
    }

    private func runCombat(dt: TimeInterval) {
        if let crown = InputController.crownIntent(delta: pendingCrown) {
            dispatch(flow.apply(crown, from: .player)); pendingCrown = 0
        }
        accumulator += dt
        while accumulator >= step {
            accumulator -= step
            if let move = ai.decide(opponent: flow.combat.opponent, player: flow.combat.player) {
                dispatch(flow.apply(move, from: .opponent))
            }
            let events = flow.tick()
            dispatch(events)
            if events.contains(where: { if case .roundOver = $0 { return true }; return false }) {
                endRound()
                break
            }
        }
    }

    private func endRound() {
        let winner = flow.combat.winner
        flow.recordRoundResult(winner)
        let ko = !flow.combat.player.isAlive || !flow.combat.opponent.isAlive
        showAnnouncer(ko ? "K.O." : "TIME", color: SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1))
        beginPhase(.roundResult)
    }

    private func afterRoundResult() {
        if flow.isMatchOver {
            let win = flow.matchWinner == .player
            showAnnouncer(win ? "YOU WIN" : "YOU LOSE",
                          color: win ? SKColor(red: 0.3, green: 1, blue: 0.5, alpha: 1)
                                     : SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1))
            beginPhase(.matchResult)
        } else {
            flow.startNextRound()
            beginPhase(.announceRound)
        }
    }

    private func dispatch(_ events: [CombatEvent]) {
        for e in events {
            Haptics.play(for: e, viewer: .player)
            switch e {
            case .heavyWindup(let s) where s == .opponent: flashTelegraph()
            case .comboHit(_, let count): showCombo(count)
            default: break
            }
        }
    }

    // MARK: - Rendering

    private func render() {
        let c = flow.combat
        let groundY = size.height * 0.42
        playerNode.position = CGPoint(x: laneToX(c.player.position) + lunge(c.player), y: groundY + 29)
        oppNode.position = CGPoint(x: laneToX(c.opponent.position) - lunge(c.opponent), y: groundY + 29)
        playerNode.alpha = c.player.isBlocking ? 0.5 : 1
        oppNode.alpha = c.opponent.isBlocking ? 0.5 : 1
        flash(playerNode, c.player.state == .hitStun || c.player.state == .launched, spec: flow.playerSpec)
        flash(oppNode, c.opponent.state == .hitStun || c.opponent.state == .launched, spec: flow.opponentSpec)

        let top = size.height - 10
        drawBar(playerHP, frac: c.player.healthFraction,
                x: 6, y: top, w: size.width/2 - 12, color: hpColor(c.player.healthFraction))
        drawBar(oppHP, frac: c.opponent.healthFraction,
                x: size.width/2 + 6, y: top, w: size.width/2 - 12,
                color: hpColor(c.opponent.healthFraction), rightAligned: true)
        drawBar(playerMeter, frac: CGFloat(c.player.meter)/100,
                x: 6, y: 5, w: size.width - 12,
                color: c.player.meterFull ? .yellow : .cyan)

        timerLabel.text = "\(max(0, c.roundTimer) / Int(CombatSystem.tickRate))"
        updatePips()
        renderProjectiles()
        telegraph.position = CGPoint(x: oppNode.position.x, y: groundY + 66)
    }

    private func renderProjectiles() {
        projectileLayer.removeAllChildren()
        let groundY = size.height * 0.42
        for p in flow.combat.projectiles {
            let dot = SKShapeNode(circleOfRadius: 5)
            let spec = p.owner == .player ? flow.playerSpec : flow.opponentSpec
            dot.fillColor = spec.accentColor.skColor
            dot.strokeColor = spec.bodyColor.skColor
            dot.glowWidth = 3
            dot.blendMode = .add
            dot.position = CGPoint(x: laneToX(p.position), y: groundY + 24)
            projectileLayer.addChild(dot)
        }
    }

    private func updatePips() {
        for (i, pip) in pipNodes.enumerated() {
            let won = i < 2 ? flow.playerRoundsWon : flow.opponentRoundsWon
            let idx = i % 2
            pip.fillColor = idx < won ? (i < 2 ? .cyan : .red) : .darkGray
        }
    }

    private func lunge(_ f: Fighter) -> CGFloat {
        f.state == .active ? max(0, (f.currentMove?.reach ?? 0)) * 0.35 * (f.facingRight ? 1 : -1) : 0
    }
    private func laneToX(_ x: CGFloat) -> CGFloat {
        let t = (x - CombatSystem.laneMin) / (CombatSystem.laneMax - CombatSystem.laneMin)
        return 18 + t * (size.width - 36)
    }
    private func hpColor(_ f: CGFloat) -> SKColor {
        f > 0.5 ? SKColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
        : f > 0.25 ? SKColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
        : SKColor(red: 1, green: 0.3, blue: 0.2, alpha: 1)
    }
    private func drawBar(_ node: SKShapeNode, frac: CGFloat, x: CGFloat, y: CGFloat,
                         w: CGFloat, color: SKColor, rightAligned: Bool = false) {
        let ww = max(0, w * frac)
        let xx = rightAligned ? x + w - ww : x
        node.path = CGPath(rect: CGRect(x: xx, y: y, width: ww, height: 7), transform: nil)
        node.fillColor = color; node.strokeColor = .clear
    }
    private func flash(_ node: SKShapeNode, _ hit: Bool, spec: CharacterSpec) {
        node.strokeColor = hit ? .white : spec.accentColor.skColor
        node.lineWidth = hit ? 3 : 2
    }
    private func flashTelegraph() {
        telegraph.removeAllActions(); telegraph.alpha = 1
        telegraph.run(.fadeOut(withDuration: 0.35))
    }
    private func showCombo(_ count: Int) {
        comboLabel.text = "\(count) HITS"
        comboLabel.removeAllActions()
        comboLabel.setScale(1.4); comboLabel.alpha = 1
        comboLabel.run(.group([.scale(to: 1.0, duration: 0.2),
                               .sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.3)])]))
    }

    // MARK: - Gesture input (forwarded from SwiftUI; watchOS has no UITouch)

    func touchDown() {
        guard phase == .fighting else { return }
        dispatch(flow.apply(.beginBlock, from: .player))
    }
    func touchUp(translation: CGSize, startLocation: CGPoint, held: TimeInterval) {
        guard phase == .fighting else { return }
        dispatch(flow.apply(.endBlock, from: .player))
        let dx = translation.width, dy = -translation.height
        if hypot(dx, dy) > 24 {
            if let intent = InputController.swipeIntent(dx: dx, dy: dy) {
                dispatch(flow.apply(intent, from: .player))
            }
        } else if held < 0.4 {
            let p = CGPoint(x: startLocation.x, y: size.height - startLocation.y)
            if flow.combat.player.meter >= CombatSystem.chargeToFire && p.x > size.width * 0.66 {
                dispatch(flow.apply(.special, from: .player))
            } else {
                dispatch(flow.apply(InputController.tapIntent(at: p, in: size), from: .player))
            }
        }
    }
}
#endif
