import CoreGraphics

/// A single animation frame expressed as joint positions in **forward-local**
/// space: origin at the fighter's feet, +y up, +x = the direction the fighter
/// faces. The renderer multiplies x by facing and offsets to screen space.
///
/// Pure value type so the whole animation system is unit-testable without
/// SpriteKit. The renderer (`SkeletonRenderer`) only draws these points.
struct Pose: Equatable {
    var pelvis: CGPoint
    var chest: CGPoint
    var head: CGPoint
    var frontHand: CGPoint
    var backHand: CGPoint
    var frontFoot: CGPoint
    var backFoot: CGPoint

    /// Linear interpolation toward another pose — used by the renderer to
    /// smooth between target poses each frame (avoids visual popping).
    func lerp(to other: Pose, _ t: CGFloat) -> Pose {
        func l(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        return Pose(pelvis: l(pelvis, other.pelvis), chest: l(chest, other.chest),
                    head: l(head, other.head), frontHand: l(frontHand, other.frontHand),
                    backHand: l(backHand, other.backHand),
                    frontFoot: l(frontFoot, other.frontFoot),
                    backFoot: l(backFoot, other.backFoot))
    }
}

/// Generates a `Pose` for a fighter's current state. Stateless + deterministic:
/// same inputs -> same pose, which keeps netplay visuals in sync.
enum Animator {

    /// Neutral standing guard with a subtle breathing bob.
    static func idle(clock: CGFloat) -> Pose {
        let bob = sin(clock * 2.2) * 1.2
        return Pose(
            pelvis: CGPoint(x: 0, y: 22 + bob * 0.4),
            chest:  CGPoint(x: -1, y: 38 + bob),
            head:   CGPoint(x: 1, y: 50 + bob),
            frontHand: CGPoint(x: 12, y: 34 + bob),
            backHand:  CGPoint(x: 4, y: 30 + bob),
            frontFoot: CGPoint(x: 9, y: 0),
            backFoot:  CGPoint(x: -9, y: 0))
    }

    /// Walking: legs + arms swing with `phase` (radians).
    static func walk(phase: CGFloat) -> Pose {
        let s = sin(phase), c = cos(phase)
        return Pose(
            pelvis: CGPoint(x: 0, y: 21),
            chest:  CGPoint(x: -1, y: 37),
            head:   CGPoint(x: 1, y: 49),
            frontHand: CGPoint(x: 11 + s * 3, y: 33),
            backHand:  CGPoint(x: 4 - s * 3, y: 30),
            frontFoot: CGPoint(x: 8 + c * 9, y: max(0, s * 5)),
            backFoot:  CGPoint(x: -8 - c * 9, y: max(0, -s * 5)))
    }

    /// Attack: `phase` 0->1 across startup+active+recovery. Different kinds
    /// extend differently (light=jab, heavy=lunge, special=both arms).
    static func attack(kind: MoveKind, phase: CGFloat) -> Pose {
        // Bell curve peaking mid-active for the strike extension.
        let strike = sin(min(max(phase, 0), 1) * .pi)
        let reach: CGFloat = kind == .light ? 16 : kind == .heavy ? 24 : 28
        let lunge: CGFloat = kind == .heavy ? 6 : kind == .special || kind == .ex ? 8 : 2
        let lowAtk: CGFloat = kind == .heavy ? -4 : 0
        return Pose(
            pelvis: CGPoint(x: lunge * strike, y: 21),
            chest:  CGPoint(x: 2 + lunge * strike, y: 38),
            head:   CGPoint(x: 3 + lunge * strike, y: 50),
            frontHand: CGPoint(x: 12 + reach * strike, y: 36 + lowAtk * strike),
            backHand:  CGPoint(x: 4 + (kind == .special || kind == .ex ? reach * strike : 0), y: 30),
            frontFoot: CGPoint(x: 9 + lunge * strike, y: 0),
            backFoot:  CGPoint(x: -10, y: 0))
    }

    /// Guarding crouch with crossed arms.
    static func block() -> Pose {
        Pose(pelvis: CGPoint(x: -2, y: 19), chest: CGPoint(x: -3, y: 34),
             head: CGPoint(x: -2, y: 46),
             frontHand: CGPoint(x: 8, y: 36), backHand: CGPoint(x: 6, y: 32),
             frontFoot: CGPoint(x: 8, y: 0), backFoot: CGPoint(x: -10, y: 0))
    }

    /// Recoiling from a hit (`phase` 0->1).
    static func hurt(phase: CGFloat) -> Pose {
        let r = sin(min(max(phase, 0), 1) * .pi)
        return Pose(
            pelvis: CGPoint(x: -4 * r, y: 21),
            chest:  CGPoint(x: -8 * r, y: 38),
            head:   CGPoint(x: -12 * r, y: 49),
            frontHand: CGPoint(x: 6 - 6 * r, y: 34),
            backHand:  CGPoint(x: 0 - 6 * r, y: 28),
            frontFoot: CGPoint(x: 8, y: 0), backFoot: CGPoint(x: -10 - 4 * r, y: 0))
    }

    /// Airborne juggle.
    static func launched(phase: CGFloat) -> Pose {
        let lift = sin(min(max(phase, 0), 1) * .pi) * 18
        return Pose(
            pelvis: CGPoint(x: -3, y: 24 + lift),
            chest:  CGPoint(x: -6, y: 40 + lift),
            head:   CGPoint(x: -9, y: 52 + lift),
            frontHand: CGPoint(x: 8, y: 46 + lift), backHand: CGPoint(x: -2, y: 44 + lift),
            frontFoot: CGPoint(x: 10, y: 6 + lift), backFoot: CGPoint(x: -8, y: 10 + lift))
    }

    /// Flat on the ground.
    static func knockdown() -> Pose {
        Pose(pelvis: CGPoint(x: -4, y: 6), chest: CGPoint(x: -14, y: 8),
             head: CGPoint(x: -24, y: 9),
             frontHand: CGPoint(x: -18, y: 4), backHand: CGPoint(x: -10, y: 3),
             frontFoot: CGPoint(x: 12, y: 4), backFoot: CGPoint(x: 4, y: 6))
    }

    /// Sharp defensive thrust.
    static func parry() -> Pose {
        Pose(pelvis: CGPoint(x: 1, y: 21), chest: CGPoint(x: 1, y: 38),
             head: CGPoint(x: 2, y: 50),
             frontHand: CGPoint(x: 22, y: 38), backHand: CGPoint(x: 6, y: 32),
             frontFoot: CGPoint(x: 10, y: 0), backFoot: CGPoint(x: -9, y: 0))
    }

    /// Top-level: choose + parameterise the pose for a fighter snapshot.
    /// `clock` is a free-running seconds timer (for idle bob / walk cadence).
    /// A tucked airborne pose (jump / jump-in).
    static func airborne() -> Pose {
        Pose(pelvis: CGPoint(x: 0, y: 20), chest: CGPoint(x: 1, y: 36),
             head: CGPoint(x: 2, y: 48),
             frontHand: CGPoint(x: 14, y: 30), backHand: CGPoint(x: -2, y: 34),
             frontFoot: CGPoint(x: 8, y: 8), backFoot: CGPoint(x: -6, y: 12))
    }

    /// Woozy dizzy sway.
    static func dizzy(clock: CGFloat) -> Pose {
        let s = sin(clock * 6) * 4
        return Pose(pelvis: CGPoint(x: s * 0.4, y: 21), chest: CGPoint(x: s, y: 37),
                    head: CGPoint(x: s * 1.5, y: 49),
                    frontHand: CGPoint(x: 6, y: 28), backHand: CGPoint(x: -2, y: 26),
                    frontFoot: CGPoint(x: 9, y: 0), backFoot: CGPoint(x: -9, y: 0))
    }

    static func pose(for f: Fighter, clock: CGFloat) -> Pose {
        // Airborne neutral overrides the ground idle pose.
        if f.airborne && f.state == .idle { return airborne() }
        switch f.state {
        case .idle:
            return f.isBlocking ? block() : idle(clock: clock)
        case .dizzy:
            return dizzy(clock: clock)
        case .startup, .active, .recovery:
            let move = f.currentMove
            let total = max(1, move?.totalDuration ?? 1)
            let done = total - f.stateTimerTotalRemaining(move: move)
            let phase = CGFloat(done) / CGFloat(total)
            return attack(kind: move?.kind ?? .light, phase: phase)
        case .blockStun:
            return block()
        case .hitStun:
            return hurt(phase: 1 - normalized(f))
        case .launched:
            return launched(phase: 1 - normalized(f))
        case .parry:
            return parry()
        case .knockdown:
            return knockdown()
        case .wakeup:
            return idle(clock: clock).lerp(to: knockdown(), 0.3)
        }
    }

    /// 0->1 progress remaining within the current timed state.
    private static func normalized(_ f: Fighter) -> CGFloat {
        guard let total = referenceDuration(f), total > 0 else { return 0 }
        return CGFloat(f.stateTimer) / CGFloat(total)
    }

    private static func referenceDuration(_ f: Fighter) -> Int? {
        switch f.state {
        case .hitStun:  return f.currentMove?.hitstun ?? 18
        case .launched: return CombatSystem.launchHitstun
        default:        return nil
        }
    }
}

extension Fighter {
    /// Ticks remaining across the whole current move (startup→active→recovery),
    /// used to compute an attack's overall animation phase.
    func stateTimerTotalRemaining(move: Move?) -> Int {
        guard let m = move else { return stateTimer }
        switch state {
        case .startup:  return stateTimer + m.active + m.recovery
        case .active:   return stateTimer + m.recovery
        case .recovery: return stateTimer
        default:        return stateTimer
        }
    }
}
