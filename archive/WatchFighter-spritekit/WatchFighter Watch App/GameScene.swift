#if os(watchOS)
import SpriteKit
import WatchKit

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
    private var holdDir = 0               // virtual-pad: -1 back, 0 none, +1 forward
    private var crownDir = 0              // crown-mode walk direction
    private var crownTimer = 0            // frames the crown walk persists after a turn
    private var pendingCrown: CGFloat = 0
    private var lastTime: TimeInterval = 0
    private var accumulator: TimeInterval = 0
    private var clock: CGFloat = 0
    private let step = 1.0 / CombatSystem.tickRate

    // Game feel ("juice")
    private let cam = SKCameraNode()
    private var hitstop = 0                 // frames the sim is frozen on impact
    private var allowHitstop = true         // off in versus to keep lockstep clean
    private var reduceMotion = false        // accessibility: skip shake/zoom

    // Secret ritual (final-boss invincibility)
    private var ritual = BossRitual()
    private let ritualLabel = SKLabelNode(text: "")
    private var isBossFight: Bool { flow.opponentSpec.guardedByRitual }

    // Nodes
    private var playerSkel: FighterRenderer!
    private var oppSkel: FighterRenderer!
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

    // One-time setup. watchOS has no `SKView`, so we do NOT override
    // `didMove(to:)` (its parameter type is `SKView`). The SwiftUI `SpriteView`
    // host drives `update(_:)`, so we set the scene up lazily on the first frame.
    private var didSetup = false
    private func setupSceneIfNeeded() {
        guard !didSetup else { return }
        didSetup = true
        SoundEngine.shared.start()
        reduceMotion = WKAccessibilityIsReduceMotionEnabled()
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
        bg.name = "stage"
        // Oversize + center so camera shake/zoom never reveals black at the edges.
        bg.setScale(1.18)
        bg.position = CGPoint(x: -size.width * 0.09, y: -size.height * 0.09)
        addChild(bg)
        isNodeTreeReady = true
    }
    private func rebuildStage() { childNode(withName: "stage")?.removeFromParent(); buildStage() }

    private func buildFighters() {
        playerSkel = Self.makeRenderer(flow.playerSpec)
        oppSkel = Self.makeRenderer(flow.opponentSpec)
        playerSkel.root.zPosition = 1; oppSkel.root.zPosition = 1
        addChild(playerSkel.root); addChild(oppSkel.root)
        projectileLayer.zPosition = 2; addChild(projectileLayer)
    }

    /// ── CHARACTER RENDERER SEAM ────────────────────────────────────────────
    /// This is the ONE place the fighter visuals are chosen. Anything conforming
    /// to `FighterRenderer` (see SkeletonRenderer.swift) drops in here with no
    /// other changes — e.g. Codex's character renderer can be committed as its
    /// own file and returned below; the rest of the game is untouched.
    ///
    /// We ship no sprite atlases, so we don't probe `SKTextureAtlas(named:)` (it
    /// can CRASH on watchOS for a missing atlas — that was the fight-scene crash).
    private static func makeRenderer(_ spec: CharacterSpec) -> FighterRenderer {
        // return CodexFighter(spec: spec)   // ← plug a new renderer in here
        SkeletonRenderer(spec: spec)
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

    /// Crown rotation: in CROWN mode it drives walking; otherwise it charges the
    /// super meter. (Rotation is the only physical control watchOS gives apps.)
    func feedCrown(delta: CGFloat) {
        if GameSettings.controls == .crown {
            if abs(delta) > 0.0008 { crownDir = delta > 0 ? 1 : -1; crownTimer = 8 }
        } else {
            pendingCrown += delta
        }
    }

    // MARK: - Phase machine

    private func beginPhase(_ p: Phase) {
        phase = p; phaseClock = 0
        switch p {
        case .announceRound: showAnnouncer("ROUND \(flow.currentRound)", color: .white)
        case .announceFight:
            showAnnouncer("FIGHT!", color: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
            SoundEngine.shared.play(.ready)
            sayBubble(.opponent, flow.opponentSpec.taunt)   // opponent trash-talks
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
        setupSceneIfNeeded()
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
        // CROWN mode: the Crown rotation drives walking (decays when you stop).
        if GameSettings.controls == .crown {
            if crownTimer > 0 { crownTimer -= 1; holdDir = crownDir } else { holdDir = 0 }
        }
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

        accumulator += dt * GameSettings.gameSpeed     // TURBO / snappy base pacing
        while accumulator >= step {
            accumulator -= step
            // Continuous walk while a direction is held (smooth, per-tick).
            if holdDir > 0 { _ = flow.apply(.walkForward, from: .player) }
            else if holdDir < 0 { _ = flow.apply(.walkBack, from: .player) }
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

    private static let koCalls = ["K.O.!", "FLATLINED!", "GOODNIGHT!", "DEMOLISHED!", "OOF.", "SAT DOWN!"]

    private func endRound() {
        let winner = flow.combat.winner
        flow.recordRoundResult(winner)
        let ko = !flow.combat.player.isAlive || !flow.combat.opponent.isAlive
        // Final, decisive KO gets a cinematic "FINISH!" beat.
        let finish = ko && flow.isMatchOver && flow.matchWinner == .player
        let text = finish ? "FINISH!" : (ko ? (FightScene.koCalls.randomElement() ?? "K.O.!") : "TIME")
        showAnnouncer(text,
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
            case .comboHit(let by, let count):
                showCombo(count)
                if count >= 3 { sayBubble(by, (by == .player ? flow.playerSpec : flow.opponentSpec).hype) }
            case .hitLanded(let attacker, let dmg):
                let victim: Side = attacker == .player ? .opponent : .player
                spawnHitSpark(at: victim, big: dmg >= 12)
                if dmg >= 12 { impactRing(at: victim) }
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
                sayBubble(s, (s == .player ? flow.playerSpec : flow.opponentSpec).hurt)
                if allowHitstop { hitstop = 6 }
                shake(9)
                koSplatter(at: s)
                koZoom(at: s)
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

    /// Bigger one-off splatter on a KO when BLOOD is enabled, plus a lingering
    /// pool on the floor that slowly fades.
    private func koSplatter(at side: Side) {
        guard GameSettings.blood else { return }
        let f = side == .player ? flow.combat.player : flow.combat.opponent
        let groundY = size.height * 0.42
        // Lingering pool.
        let pool = SKShapeNode(ellipseOf: CGSize(width: CGFloat.random(in: 26...40), height: 8))
        pool.fillColor = SKColor(red: 0.45, green: 0.02, blue: 0.04, alpha: 0.9)
        pool.strokeColor = .clear
        pool.position = CGPoint(x: laneToX(f.position), y: groundY + 2)
        pool.zPosition = 0
        addChild(pool)
        pool.setScale(0.2)
        pool.run(.sequence([.scale(to: 1.0, duration: 0.3),
                            .wait(forDuration: 3.5),
                            .fadeOut(withDuration: 1.5), .removeFromParent()]))

        let origin = CGPoint(x: laneToX(f.position), y: groundY + 28)
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

    /// A character "voice": a small speech bubble above a fighter that fades.
    /// One bubble per side at a time (named nodes) so they don't spam.
    private func sayBubble(_ side: Side, _ text: String) {
        guard !text.isEmpty else { return }
        let name = side == .player ? "bubble_p" : "bubble_o"
        if childNode(withName: name) != nil { return }
        let c = flow.combat
        let f = side == .player ? c.player : c.opponent
        let spec = side == .player ? flow.playerSpec : flow.opponentSpec

        let label = SKLabelNode(text: text)
        label.fontName = "Menlo-Bold"; label.fontSize = 9
        label.fontColor = .black
        label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .center
        let w = max(28, label.frame.width + 10)
        let bubble = SKShapeNode(rectOf: CGSize(width: w, height: 16), cornerRadius: 6)
        bubble.fillColor = spec.accentColor.skColor
        bubble.strokeColor = .white
        bubble.lineWidth = 1
        bubble.name = name
        bubble.zPosition = 8
        bubble.addChild(label)
        bubble.position = CGPoint(x: laneToX(f.position), y: size.height * 0.42 + 78 + f.height)
        bubble.alpha = 0
        bubble.setScale(0.6)
        addChild(bubble)
        bubble.run(.sequence([
            .group([.fadeIn(withDuration: 0.1), .scale(to: 1, duration: 0.12)]),
            .wait(forDuration: 1.1),
            .fadeOut(withDuration: 0.3), .removeFromParent()]))
    }

    /// A popping shockwave ring on heavy impacts — expands and fades for that
    /// "WOW" hit feedback. Additive so it reads as a flash of energy.
    private func impactRing(at side: Side) {
        let c = flow.combat
        let f = side == .player ? c.player : c.opponent
        let spec = side == .player ? flow.playerSpec : flow.opponentSpec
        let ring = SKShapeNode(circleOfRadius: 8)
        ring.strokeColor = spec.accentColor.skColor
        ring.fillColor = .clear
        ring.lineWidth = 3
        ring.glowWidth = 2
        ring.blendMode = .add
        ring.position = CGPoint(x: laneToX(f.position), y: size.height * 0.42 + 30)
        ring.zPosition = 4
        addChild(ring)
        ring.run(.sequence([.group([.scale(to: 3.2, duration: 0.22),
                                    .fadeOut(withDuration: 0.22)]), .removeFromParent()]))
    }

    /// Camera shake for impact weight. No-op visual; never touches the sim.
    /// Skipped entirely when the system Reduce Motion setting is on.
    private func shake(_ intensity: CGFloat) {
        guard !reduceMotion else { return }
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

    /// Cinematic punch-in on the loser for a decisive KO. Restores afterwards.
    private func koZoom(at side: Side) {
        guard !reduceMotion else { return }
        let f = side == .player ? flow.combat.player : flow.combat.opponent
        // Clamp the zoom target so the (scaled) view stays inside the stage —
        // otherwise zooming on an edge fighter reveals/distorts the border.
        let zoom: CGFloat = 0.82
        let halfW = size.width * zoom / 2, halfH = size.height * zoom / 2
        let tx = min(max(laneToX(f.position), halfW), size.width - halfW)
        let target = CGPoint(x: tx, y: min(max(size.height * 0.5, halfH), size.height - halfH))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        cam.removeAction(forKey: "kozoom")
        cam.run(.sequence([
            .group([.move(to: target, duration: 0.12), .scale(to: zoom, duration: 0.12)]),
            .wait(forDuration: 0.18),
            .group([.move(to: center, duration: 0.22), .scale(to: 1.0, duration: 0.22)]),
        ]), withKey: "kozoom")
    }

    // MARK: - Gesture input (forwarded from SwiftUI; queued, not applied directly)

    // MARK: - Virtual gamepad (preferred) — discrete button presses

    /// Hold-to-walk direction: -1 back, +1 forward, 0 release.
    func padMove(_ dir: Int) { holdDir = (phase == .fighting) ? dir : 0 }

    /// A tap action button (light/heavy/special/grab/parry/jump).
    func padTap(_ intent: Intent) {
        guard phase == .fighting else { return }
        pendingLocal.append(intent)
        switch intent {
        case .heavyAttack: SoundEngine.shared.play(.heavy)
        case .lightAttack: SoundEngine.shared.play(.light)
        case .special:     SoundEngine.shared.play(.special)
        case .parry:       SoundEngine.shared.play(.parry)
        default: break
        }
    }

    func padBlock(_ down: Bool) {
        guard phase == .fighting else { return }
        pendingLocal.append(down ? .beginBlock : .endBlock)
    }

    // MARK: - Gesture scheme (only when the virtual pad is OFF)

    func touchDown() {
        guard phase == .fighting, GameSettings.controls == .gestures else { return }
        pendingLocal.append(.beginBlock)
    }
    func touchUp(translation: CGSize, startLocation: CGPoint, held: TimeInterval) {
        guard phase == .fighting, GameSettings.controls == .gestures else { return }
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
