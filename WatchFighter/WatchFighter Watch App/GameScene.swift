#if os(watchOS)
import SpriteKit

/// What drives the opponent and how the round loop runs.
enum FightMode {
    case story(AIController.Difficulty)
    case training(TrainingOptions)
    /// Lockstep PvP. `localSide` says which fighter this device controls.
    case versus(localSide: Side, transport: MatchTransport)
}

/// Runs a best-of-three match with full presentation: announcer beats, parallax
/// stage, skeletal fighters, health bars + round pips, super meter, combo
/// counter, projectiles, haptics, and synthesised SFX. Supports vs-CPU (story),
/// training, and experimental lockstep versus. Reports the winner via `onResult`.
final class FightScene: SKScene {

    // Config
    private let stageSpec: StageSpec
    private let mode: FightMode
    private var flow: MatchFlow
    private let onResult: (Side) -> Void
    private var resultReported = false

    // Opponent control (story/training)
    private var ai = AIController(difficulty: .normal)
    private var dummy: TrainingDummy?
    private var trainingOptions: TrainingOptions?

    // Versus (lockstep)
    private var session: LockstepSession?
    private var transport: MatchTransport?

    // Presentation phases
    private enum Phase { case announceRound, announceFight, fighting, roundResult, matchResult }
    private var phase: Phase = .announceRound
    private var phaseClock: TimeInterval = 0

    // Loop bookkeeping
    private var pendingLocal: [Intent] = []
    private var pendingCrown: CGFloat = 0
    private var lastTime: TimeInterval = 0
    private var accumulator: TimeInterval = 0
    private var clock: CGFloat = 0
    private let step = 1.0 / CombatSystem.tickRate

    // Game feel ("juice")
    private let cam = SKCameraNode()
    private var hitstop = 0                 // frames the sim is frozen on impact
    private var allowHitstop = true         // off in versus to keep lockstep clean

    // Secret ritual (final-boss invincibility)
    private var ritual = BossRitual()
    private let ritualLabel = SKLabelNode(text: "")
    private var isBossFight: Bool { flow.opponentSpec.guardedByRitual }

    // Nodes
    private var playerSkel: SkeletonRenderer!
    private var oppSkel: SkeletonRenderer!
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
    private let frameDataLabel = SKLabelNode(text: "")

    init(playerSpec: CharacterSpec, opponentSpec: CharacterSpec,
         stage: StageSpec, mode: FightMode,
         onResult: @escaping (Side) -> Void) {
        self.stageSpec = stage
        self.mode = mode
        self.flow = MatchFlow(playerSpec: playerSpec, opponentSpec: opponentSpec)
        self.onResult = onResult
        super.init(size: CGSize(width: 200, height: 240))
        scaleMode = .resizeFill
        configureMode()
    }
    required init?(coder: NSCoder) { fatalError("use init(playerSpec:…)") }

    private func configureMode() {
        switch mode {
        case .story(let diff):
            ai = AIController(difficulty: diff)
        case .training(let opts):
            trainingOptions = opts
            dummy = TrainingDummy(options: opts)
        case .versus(let localSide, let transport):
            allowHitstop = false      // keep deterministic lockstep pacing clean
            self.transport = transport
            self.session = LockstepSession(localSide: localSide)
            transport.onReceive = { [weak self] message in
                guard case .input(let frame) = message else { return }   // setup done in lobby
                DispatchQueue.main.async { self?.session?.receiveRemote(frame) }
            }
            transport.onDisconnect = { [weak self] in
                DispatchQueue.main.async { self?.forfeitVersus() }
            }
        }
    }

    override func didMove(to view: SKView) {
        SoundEngine.shared.start()
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cam)
        camera = cam
        buildStage()
        buildFighters()
        buildHUD()
        beginPhase(.announceRound)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard isNodeTreeReady else { return }
        cam.removeAllActions()
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
        rebuildStage(); layoutHUD()
    }
    private var isNodeTreeReady = false

    // MARK: - Build

    private func buildStage() {
        let bg = StageBuilder.build(stageSpec, size: size)
        bg.name = "stage"; addChild(bg)
        isNodeTreeReady = true
    }
    private func rebuildStage() { childNode(withName: "stage")?.removeFromParent(); buildStage() }

    private func buildFighters() {
        playerSkel = SkeletonRenderer(spec: flow.playerSpec)
        oppSkel = SkeletonRenderer(spec: flow.opponentSpec)
        playerSkel.root.zPosition = 1; oppSkel.root.zPosition = 1
        addChild(playerSkel.root); addChild(oppSkel.root)
        projectileLayer.zPosition = 2; addChild(projectileLayer)
    }

    private func buildHUD() {
        [playerHPBack, oppHPBack, playerHP, oppHP, playerMeter].forEach { $0.zPosition = 5; addChild($0) }
        styleLabel(nameLabelP, size: 9); nameLabelP.text = flow.playerSpec.name
        styleLabel(nameLabelO, size: 9); nameLabelO.text = flow.opponentSpec.name
        styleLabel(timerLabel, size: 12)
        styleLabel(comboLabel, size: 13); comboLabel.fontColor = .yellow; comboLabel.alpha = 0
        styleLabel(announcer, size: 22); announcer.alpha = 0
        styleLabel(telegraph, size: 24); telegraph.fontColor = .yellow; telegraph.alpha = 0
        styleLabel(frameDataLabel, size: 8); frameDataLabel.fontColor = .green
        frameDataLabel.horizontalAlignmentMode = .left
        frameDataLabel.alpha = (trainingOptions?.showFrameData == true) ? 1 : 0
        styleLabel(ritualLabel, size: 9); ritualLabel.fontColor = .yellow
        ritualLabel.alpha = isBossFight ? 1 : 0
        [nameLabelP, nameLabelO, timerLabel, comboLabel, announcer, telegraph,
         frameDataLabel, ritualLabel].forEach { $0.zPosition = 6; addChild($0) }
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
        [playerHPBack, oppHPBack].forEach { $0.fillColor = SKColor(white: 0.15, alpha: 1); $0.strokeColor = .clear }
        playerHPBack.path = barRect(x: 6, y: top, w: size.width/2 - 12)
        oppHPBack.path = barRect(x: size.width/2 + 6, y: top, w: size.width/2 - 12)
        nameLabelP.position = CGPoint(x: 6, y: top - 12); nameLabelP.horizontalAlignmentMode = .left
        nameLabelO.position = CGPoint(x: size.width - 6, y: top - 12); nameLabelO.horizontalAlignmentMode = .right
        timerLabel.position = CGPoint(x: size.width/2, y: top - 2)
        announcer.position = CGPoint(x: size.width/2, y: size.height * 0.62)
        comboLabel.position = CGPoint(x: size.width * 0.28, y: size.height * 0.55)
        frameDataLabel.position = CGPoint(x: 4, y: size.height * 0.34)
        ritualLabel.position = CGPoint(x: size.width / 2, y: 16)
        for (i, pip) in pipNodes.enumerated() {
            let idx = CGFloat(i % 2)
            pip.position = CGPoint(x: i < 2 ? 8 + idx * 9 : size.width - 8 - idx * 9, y: top - 22)
        }
    }
    private func barRect(x: CGFloat, y: CGFloat, w: CGFloat) -> CGPath {
        CGPath(rect: CGRect(x: x, y: y, width: max(0, w), height: 7), transform: nil)
    }

    // MARK: - Crown

    func feedCrown(delta: CGFloat) { pendingCrown += delta }

    // MARK: - Phase machine

    private func beginPhase(_ p: Phase) {
        phase = p; phaseClock = 0
        switch p {
        case .announceRound: showAnnouncer("ROUND \(flow.currentRound)", color: .white)
        case .announceFight:
            showAnnouncer("FIGHT!", color: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
            SoundEngine.shared.play(.ready)
        case .fighting: accumulator = 0; announcer.run(.fadeOut(withDuration: 0.2))
        case .roundResult, .matchResult: break
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
        clock += CGFloat(dt)

        switch phase {
        case .announceRound: if phaseClock > 1.1 { beginPhase(.announceFight) }
        case .announceFight: if phaseClock > 0.7 { beginPhase(.fighting) }
        case .fighting: stepFighting(dt: dt)
        case .roundResult: if phaseClock > 1.5 { afterRoundResult() }
        case .matchResult:
            if phaseClock > 1.6 && !resultReported {
                resultReported = true
                transport?.disconnect()
                onResult(flow.matchWinner ?? .opponent)
            }
        }
        render()
    }

    private func drainCrownIntoPending() {
        if let crown = InputController.crownIntent(delta: pendingCrown) {
            pendingLocal.append(crown); pendingCrown = 0
        }
    }

    private func stepFighting(dt: TimeInterval) {
        // Hitstop: freeze the sim a few frames on impact for punchy feedback.
        if hitstop > 0 { hitstop -= 1; return }
        drainCrownIntoPending()
        switch mode {
        case .story, .training: stepLocalAuthoritative(dt: dt)
        case .versus:           stepVersus()
        }
    }

    /// vs-CPU / training: this device owns the whole simulation.
    private func stepLocalAuthoritative(dt: TimeInterval) {
        // Apply local inputs once per frame; feed the boss ritual tracker.
        for intent in pendingLocal {
            dispatch(flow.apply(intent, from: .player))
            if isBossFight && !flow.combat.ritualBroken && ritual.note(intent) {
                onRitualComplete()
            }
        }
        pendingLocal.removeAll()

        accumulator += dt
        while accumulator >= step {
            accumulator -= step
            if let opts = trainingOptions {
                flow.applyTraining(opts)
                if let d = dummy?.decide(dummy: flow.combat.opponent, player: flow.combat.player) {
                    dispatch(flow.apply(d, from: .opponent))
                }
            } else if let move = ai.decide(opponent: flow.combat.opponent, player: flow.combat.player) {
                dispatch(flow.apply(move, from: .opponent))
            }
            let events = flow.tick()
            dispatch(events)
            if events.contains(where: { if case .roundOver = $0 { return true }; return false }) {
                if trainingOptions != nil { flow.resetCurrentRound() }   // never-ending practice
                else { endRound(); break }
            }
        }
    }

    /// Experimental lockstep PvP. Submits one input frame per render frame and
    /// advances the deterministic sim as far as exchanged inputs allow.
    private func stepVersus() {
        guard let s = session else { return }
        let frame = s.submitLocal(pendingLocal)
        pendingLocal.removeAll()
        transport?.send(.input(frame))

        var advanced = 0
        while advanced < 4, let (p, o) = s.consumeCurrentTick() {
            for i in p { dispatch(flow.apply(i, from: .player)) }
            for i in o { dispatch(flow.apply(i, from: .opponent)) }
            let events = flow.tick()
            dispatch(events)
            advanced += 1
            if events.contains(where: { if case .roundOver = $0 { return true }; return false }) {
                endRound(); return
            }
        }
    }

    private func forfeitVersus() {
        guard !resultReported else { return }
        showAnnouncer("OPPONENT LEFT", color: .red)
        flow.recordRoundResult(.player); flow.recordRoundResult(.player)
        beginPhase(.matchResult)
    }

    /// The player nailed the secret process — the boss is mortal at last.
    private func onRitualComplete() {
        flow.breakRitualGuard()
        showAnnouncer("THE BELL RINGS!", color: SKColor(red: 1, green: 0.85, blue: 0.25, alpha: 1))
        SoundEngine.shared.play(.ready)
        shake(12)
    }

    private func endRound() {
        let winner = flow.combat.winner
        flow.recordRoundResult(winner)
        let ko = !flow.combat.player.isAlive || !flow.combat.opponent.isAlive
        // Final, decisive KO gets a cinematic "FINISH!" beat.
        let finish = ko && flow.isMatchOver && flow.matchWinner == .player
        showAnnouncer(finish ? "FINISH!" : (ko ? "K.O." : "TIME"),
                      color: finish ? SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
                                    : SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 1))
        SoundEngine.shared.play(.ko)
        if finish { shake(14); if allowHitstop { hitstop = 10 } }
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
            flow.startNextRound(); beginPhase(.announceRound)
        }
    }

    private func dispatch(_ events: [CombatEvent]) {
        for e in events {
            Haptics.play(for: e, viewer: .player)
            SoundEngine.shared.play(for: e, viewer: .player)
            switch e {
            case .heavyWindup(let s) where s == .opponent:
                flashTelegraph()
            case .comboHit(_, let count):
                showCombo(count)
            case .hitLanded(let attacker, let dmg):
                let victim: Side = attacker == .player ? .opponent : .player
                spawnHitSpark(at: victim, big: dmg >= 12)
                if allowHitstop { hitstop = dmg >= 12 ? 4 : 2 }
                shake(dmg >= 12 ? 6 : 3)
            case .armorAbsorbed(let s):
                spawnHitSpark(at: s, big: false)
                SoundEngine.shared.play(.block)
                shake(2)
            case .invulnerable(let s):
                spawnHitSpark(at: s, big: false)
                SoundEngine.shared.play(.block)   // metallic "clank" — no effect
                shake(1)
            case .knockdown(let s):
                if allowHitstop { hitstop = 6 }
                shake(9)
                koSplatter(at: s)
            case .parried(let by):
                spawnHitSpark(at: by, big: true)
                shake(4)
            case .thrown(let s):
                spawnHitSpark(at: s, big: true)
                if allowHitstop { hitstop = 5 }
                shake(8)
            case .dizzy(let s):
                spawnHitSpark(at: s, big: true)
                showAnnouncer("DIZZY!", color: SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1))
                shake(5)
            case .throwTeched:
                shake(3)
            default: break
            }
        }
    }

    // MARK: - Rendering

    private func render() {
        let c = flow.combat
        let groundY = size.height * 0.42
        playerSkel.update(for: c.player, clock: clock, originX: laneToX(c.player.position),
                          groundY: groundY, flashHit: false)
        oppSkel.update(for: c.opponent, clock: clock + 1.3, originX: laneToX(c.opponent.position),
                       groundY: groundY, flashHit: false)

        let top = size.height - 10
        drawBar(playerHP, frac: c.player.healthFraction, x: 6, y: top, w: size.width/2 - 12,
                color: hpColor(c.player.healthFraction))
        drawBar(oppHP, frac: c.opponent.healthFraction, x: size.width/2 + 6, y: top, w: size.width/2 - 12,
                color: hpColor(c.opponent.healthFraction), rightAligned: true)
        drawBar(playerMeter, frac: CGFloat(c.player.meter)/100, x: 6, y: 5, w: size.width - 12,
                color: c.player.meterFull ? .yellow : .cyan)

        timerLabel.text = "\(max(0, c.roundTimer) / Int(CombatSystem.tickRate))"
        updatePips(); renderProjectiles()
        telegraph.position = CGPoint(x: laneToX(c.opponent.position), y: groundY + 70)
        if trainingOptions?.showFrameData == true { updateFrameData(c) }
        if isBossFight { updateRitualHint(c) }
    }

    /// Boss fight HUD: shows the secret process + progress, or "MORTAL" once
    /// the bell has been rung. Without this, the boss is unbeatable on purpose.
    private func updateRitualHint(_ c: CombatSystem) {
        if c.ritualBroken {
            ritualLabel.text = "TITUS IS MORTAL"
            ritualLabel.fontColor = SKColor(red: 0.4, green: 1, blue: 0.5, alpha: 1)
        } else {
            let seq = BossRitual.glyphs.enumerated().map { i, g in
                i < ritual.progress ? "[\(g)]" : g
            }.joined(separator: " ")
            ritualLabel.text = "RING THE BELL  \(seq)"
            ritualLabel.fontColor = .yellow
        }
    }

    private func updateFrameData(_ c: CombatSystem) {
        frameDataLabel.text = "P:\(stateTag(c.player))  O:\(stateTag(c.opponent))"
    }
    private func stateTag(_ f: Fighter) -> String {
        switch f.state {
        case .idle: return "idle"
        case .startup: return "start\(f.stateTimer)"
        case .active: return "ACT\(f.stateTimer)"
        case .recovery: return "rec\(f.stateTimer)"
        case .blockStun: return "blk\(f.stateTimer)"
        case .hitStun: return "hit\(f.stateTimer)"
        case .launched: return "air\(f.stateTimer)"
        case .parry: return "PRY\(f.stateTimer)"
        case .knockdown: return "down"
        case .wakeup: return "wake"
        case .dizzy: return "DIZZY"
        }
    }

    private func renderProjectiles() {
        projectileLayer.removeAllChildren()
        let groundY = size.height * 0.42
        for p in flow.combat.projectiles {
            let dot = SKShapeNode(circleOfRadius: 5)
            let spec = p.owner == .player ? flow.playerSpec : flow.opponentSpec
            dot.fillColor = spec.accentColor.skColor; dot.strokeColor = spec.bodyColor.skColor
            dot.glowWidth = 3; dot.blendMode = .add
            dot.position = CGPoint(x: laneToX(p.position), y: groundY + 30)
            projectileLayer.addChild(dot)
        }
    }
    private func updatePips() {
        for (i, pip) in pipNodes.enumerated() {
            let won = i < 2 ? flow.playerRoundsWon : flow.opponentRoundsWon
            pip.fillColor = (i % 2) < won ? (i < 2 ? .cyan : .red) : .darkGray
        }
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
        let ww = max(0, w * frac); let xx = rightAligned ? x + w - ww : x
        node.path = CGPath(rect: CGRect(x: xx, y: y, width: ww, height: 7), transform: nil)
        node.fillColor = color; node.strokeColor = .clear
    }
    private func flashTelegraph() {
        telegraph.removeAllActions(); telegraph.alpha = 1
        telegraph.run(.fadeOut(withDuration: 0.35))
    }
    private func showCombo(_ count: Int) {
        let praise = count >= 6 ? "SAVAGE!" : count >= 4 ? "BRUTAL!" : count >= 3 ? "NICE!" : ""
        comboLabel.text = praise.isEmpty ? "\(count) HITS" : "\(count) HITS  \(praise)"
        comboLabel.fontColor = count >= 6 ? .red : count >= 4 ? .orange : .yellow
        comboLabel.removeAllActions(); comboLabel.setScale(1.4); comboLabel.alpha = 1
        comboLabel.run(.group([.scale(to: 1.0, duration: 0.2),
                               .sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.3)])]))
    }

    /// Quick burst of shards at the victim's position. Uses the attacker's
    /// accent colour normally, or red gore when the optional BLOOD setting is on.
    private func spawnHitSpark(at side: Side, big: Bool) {
        let c = flow.combat
        let f = side == .player ? c.player : c.opponent
        let spec = side == .player ? flow.playerSpec : flow.opponentSpec
        let origin = CGPoint(x: laneToX(f.position), y: size.height * 0.42 + 32)
        let gore = GameSettings.blood
        let color: SKColor = gore ? SKColor(red: 0.75, green: 0.05, blue: 0.08, alpha: 1)
                                  : spec.accentColor.skColor
        let shards = (big ? 8 : 5) + (gore ? 4 : 0)
        for _ in 0..<shards {
            let s = big ? 4 : 3
            let shard = SKShapeNode(rectOf: CGSize(width: s, height: s))
            shard.fillColor = color
            shard.strokeColor = .clear
            shard.blendMode = gore ? .alpha : .add
            shard.position = origin
            shard.zPosition = 4
            addChild(shard)
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let dist = CGFloat.random(in: 8...(big ? 26 : 16)) * (gore ? 1.3 : 1)
            // Gore arcs downward (gravity); sparks fly straight out.
            let dy = gore ? cos(angle) * dist - 10 : sin(angle) * dist
            let move = SKAction.move(by: CGVector(dx: cos(angle) * dist, dy: dy), duration: 0.24)
            move.timingMode = .easeOut
            shard.run(.sequence([.group([move, .fadeOut(withDuration: 0.24),
                                         .scale(to: 0.2, duration: 0.24)]), .removeFromParent()]))
        }
    }

    /// Bigger one-off splatter on a KO when BLOOD is enabled.
    private func koSplatter(at side: Side) {
        guard GameSettings.blood else { return }
        let f = side == .player ? flow.combat.player : flow.combat.opponent
        let origin = CGPoint(x: laneToX(f.position), y: size.height * 0.42 + 28)
        for _ in 0..<16 {
            let drop = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.5...3.5))
            drop.fillColor = SKColor(red: 0.6, green: 0.03, blue: 0.05, alpha: 1)
            drop.strokeColor = .clear
            drop.position = origin
            drop.zPosition = 4
            addChild(drop)
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let dist = CGFloat.random(in: 14...40)
            let move = SKAction.move(by: CGVector(dx: cos(angle) * dist, dy: sin(angle) * dist - 14),
                                     duration: 0.4)
            move.timingMode = .easeOut
            drop.run(.sequence([.group([move, .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
        }
    }

    /// Camera shake for impact weight. No-op visual; never touches the sim.
    private func shake(_ intensity: CGFloat) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        cam.removeAction(forKey: "shake")
        var steps: [SKAction] = []
        for _ in 0..<5 {
            let dx = CGFloat.random(in: -intensity...intensity)
            let dy = CGFloat.random(in: -intensity...intensity)
            steps.append(.move(to: CGPoint(x: center.x + dx, y: center.y + dy), duration: 0.02))
        }
        steps.append(.move(to: center, duration: 0.03))
        cam.run(.sequence(steps), withKey: "shake")
    }

    // MARK: - Gesture input (forwarded from SwiftUI; queued, not applied directly)

    func touchDown() {
        guard phase == .fighting else { return }
        pendingLocal.append(.beginBlock)
    }
    func touchUp(translation: CGSize, startLocation: CGPoint, held: TimeInterval) {
        guard phase == .fighting else { return }
        pendingLocal.append(.endBlock)
        let dx = translation.width, dy = -translation.height
        if hypot(dx, dy) > 24 {
            if let intent = InputController.swipeIntent(dx: dx, dy: dy) {
                pendingLocal.append(intent)
                if intent == .parry { SoundEngine.shared.play(.parry) }
            }
        } else if held < 0.4 {
            let p = CGPoint(x: startLocation.x, y: size.height - startLocation.y)
            if p.x < size.width * 0.2 {
                pendingLocal.append(.grab); SoundEngine.shared.play(.heavy)   // far-left = throw
            } else if flow.combat.player.meter >= CombatSystem.chargeToFire && p.x > size.width * 0.66 {
                pendingLocal.append(.special); SoundEngine.shared.play(.special)
            } else {
                let intent = InputController.tapIntent(at: p, in: size)
                pendingLocal.append(intent)
                SoundEngine.shared.play(intent == .heavyAttack ? .heavy : .light)
            }
        }
    }
}
#endif
