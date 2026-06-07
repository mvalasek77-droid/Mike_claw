import XCTest
@testable import WatchFighter_Watch_App

/// Tests for M2: deterministic lockstep netcode, serialization, training, and
/// the pure animation system.
final class NetcodeTests: XCTestCase {

    func testInputFrameCodableRoundTrip() throws {
        let frame = InputFrame(tick: 42, intents: [.lightAttack, .charge(0.5), .stepForward])
        let data = try JSONEncoder().encode(frame)
        let back = try JSONDecoder().decode(InputFrame.self, from: data)
        XCTAssertEqual(frame, back)
    }

    /// Two "devices" running independent sims must stay byte-for-byte in sync
    /// when fed the same exchanged inputs — the core promise of lockstep.
    func testLockstepKeepsTwoSimsInSync() {
        let a = LockstepSession(localSide: .player, inputDelay: 2)
        let b = LockstepSession(localSide: .opponent, inputDelay: 2)
        var simA = CombatSystem(playerSpec: .tetsu, opponentSpec: .volt)
        var simB = CombatSystem(playerSpec: .tetsu, opponentSpec: .volt)

        func drive(_ s: LockstepSession, _ sim: inout CombatSystem) {
            while let (p, o) = s.consumeCurrentTick() {
                for i in p { _ = sim.apply(i, from: .player) }
                for i in o { _ = sim.apply(i, from: .opponent) }
                _ = sim.tick()
            }
        }

        for frame in 0..<150 {
            let aLocal: [Intent] = frame == 10 ? [.stepForward] : (frame == 20 ? [.lightAttack] : [])
            let bLocal: [Intent] = frame == 15 ? [.beginBlock] : (frame == 40 ? [.heavyAttack] : [])
            let fa = a.submitLocal(aLocal)
            let fb = b.submitLocal(bLocal)
            a.receiveRemote(fb); b.receiveRemote(fa)
            drive(a, &simA); drive(b, &simB)
        }

        XCTAssertEqual(simA.player.health, simB.player.health)
        XCTAssertEqual(simA.opponent.health, simB.opponent.health)
        XCTAssertEqual(simA.player.position, simB.player.position)
        XCTAssertEqual(simA.opponent.position, simB.opponent.position)
        XCTAssertEqual(a.currentTick, b.currentTick)
    }

    func testLockstepStallsWithoutRemoteInput() {
        let a = LockstepSession(localSide: .player, inputDelay: 2)
        // Submit locals but never deliver remote -> cannot pass the pre-filled window.
        for _ in 0..<5 { _ = a.submitLocal([]) }
        var advanced = 0
        while a.consumeCurrentTick() != nil { advanced += 1; if advanced > 100 { break } }
        XCTAssertEqual(advanced, 2, "only the pre-filled delay window should advance")
    }

    func testLoopbackTransportDelivers() {
        let (a, b) = LoopbackTransport.pair()
        var received: InputFrame?
        b.onReceiveFrame = { received = $0 }
        a.send(InputFrame(tick: 7, intents: [.special]))
        XCTAssertEqual(received, InputFrame(tick: 7, intents: [.special]))
    }

    func testTrainingDummyBlocks() {
        var dummy = TrainingDummy(options: TrainingOptions(dummyBehavior: .block))
        let player = Fighter(spec: .tetsu, facingRight: true, position: 120)
        var me = Fighter(spec: .bastion, facingRight: false, position: 280)
        XCTAssertEqual(dummy.decide(dummy: me, player: player), .beginBlock)
        me.isBlocking = true
        XCTAssertNil(dummy.decide(dummy: me, player: player))
    }

    func testTrainingDummyStandDoesNothing() {
        var dummy = TrainingDummy(options: TrainingOptions(dummyBehavior: .stand))
        let player = Fighter(spec: .tetsu, facingRight: true, position: 120)
        let me = Fighter(spec: .bastion, facingRight: false, position: 280)
        XCTAssertNil(dummy.decide(dummy: me, player: player))
    }

    func testAnimatorPosesAreDistinct() {
        let idle = Animator.idle(clock: 0)
        let down = Animator.knockdown()
        XCTAssertLessThan(down.head.y, idle.head.y, "head is lower when knocked down")

        let extended = Animator.attack(kind: .heavy, phase: 0.5)
        XCTAssertGreaterThan(extended.frontHand.x, idle.frontHand.x, "attack extends the front hand")
    }

    func testPoseLerpInterpolates() {
        let a = Animator.idle(clock: 0)
        let b = Animator.knockdown()
        let mid = a.lerp(to: b, 0.5)
        XCTAssertEqual(mid.head.y, (a.head.y + b.head.y) / 2, accuracy: 0.001)
    }
}
