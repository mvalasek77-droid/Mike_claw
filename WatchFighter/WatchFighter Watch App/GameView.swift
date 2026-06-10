#if os(watchOS)
import SwiftUI
import SpriteKit

/// Hosts a single match's `FightScene`, the on-screen virtual gamepad (default
/// control scheme), the Digital Crown (charges the super meter), and the exit
/// button. Recreated per fight via `.id(...)` from the parent.
struct FightView: View {
    @State private var crownValue = 0.0
    @State private var lastCrown = 0.0
    @State private var dragStart: Date?
    @State private var usePad = GameSettings.virtualPad
    @FocusState private var focused: Bool
    @State private var scene: FightScene
    let onExit: () -> Void

    init(playerSpec: CharacterSpec, opponentSpec: CharacterSpec,
         stage: StageSpec, mode: FightMode,
         onResult: @escaping (Side) -> Void, onExit: @escaping () -> Void) {
        self.onExit = onExit
        _scene = State(initialValue: FightScene(
            playerSpec: playerSpec, opponentSpec: opponentSpec,
            stage: stage, mode: mode, onResult: onResult))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpriteView(scene: scene)
                .ignoresSafeArea()
                .focusable(true)
                .focused($focused)
                .digitalCrownRotation(
                    $crownValue, from: -1_000_000, through: 1_000_000,
                    by: 0.01, sensitivity: .medium,
                    isContinuous: true, isHapticFeedbackEnabled: false)
                .onChange(of: crownValue) { _, newValue in
                    let delta = newValue - lastCrown
                    lastCrown = newValue
                    scene.feedCrown(delta: CGFloat(delta))
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { _ in
                            if dragStart == nil { dragStart = Date(); scene.touchDown() }
                        }
                        .onEnded { value in
                            let held = dragStart.map { Date().timeIntervalSince($0) } ?? 0
                            scene.touchUp(translation: value.translation,
                                          startLocation: value.startLocation, held: held)
                            dragStart = nil
                        }
                )

            if usePad { gamepad }

            // Always-available exit — no mode (esp. endless Training) can soft-lock.
            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain).padding(.leading, 3).padding(.top, 1)
            .accessibilityLabel("Quit match")
        }
        .onAppear { focused = true }
    }

    /// On-screen virtual gamepad: hold-to-walk D-pad on the left, action buttons
    /// on the right, block + jump in the corners. Crown still charges the meter.
    private var gamepad: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                // Left: movement
                VStack(spacing: 3) {
                    PadButton("↑") { scene.padTap(.jump) }
                    HStack(spacing: 3) {
                        HoldButton("◀", onDown: { scene.padMove(-1) }, onUp: { scene.padMove(0) })
                        HoldButton("▶", onDown: { scene.padMove(1) }, onUp: { scene.padMove(0) })
                    }
                    HoldButton("BLK", tint: .blue,
                               onDown: { scene.padBlock(true) }, onUp: { scene.padBlock(false) })
                }
                Spacer()
                // Right: attacks
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        PadButton("L", tint: .cyan) { scene.padTap(.lightAttack) }
                        PadButton("H", tint: .orange) { scene.padTap(.heavyAttack) }
                    }
                    HStack(spacing: 3) {
                        PadButton("S", tint: .yellow) { scene.padTap(.special) }
                        PadButton("GR", tint: .purple) { scene.padTap(.grab) }
                    }
                    PadButton("P", tint: .green) { scene.padTap(.parry) }
                }
            }
            .padding(.horizontal, 3).padding(.bottom, 2)
        }
        .ignoresSafeArea()
    }
}

/// Round tap button for the virtual gamepad.
struct PadButton: View {
    let label: String
    var tint: Color = .white
    let action: () -> Void
    init(_ label: String, tint: Color = .white, action: @escaping () -> Void) {
        self.label = label; self.tint = tint; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .black)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.35)))
                .overlay(Circle().stroke(tint.opacity(0.85), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Press-and-hold button (direction / block) — reports down + up edges.
struct HoldButton: View {
    let label: String
    var tint: Color = .white
    let onDown: () -> Void
    let onUp: () -> Void
    @State private var held = false
    init(_ label: String, tint: Color = .white,
         onDown: @escaping () -> Void, onUp: @escaping () -> Void) {
        self.label = label; self.tint = tint; self.onDown = onDown; self.onUp = onUp
    }
    var body: some View {
        Text(label).font(.system(size: 11, weight: .black)).foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(tint.opacity(held ? 0.7 : 0.35)))
            .overlay(Circle().stroke(tint.opacity(0.85), lineWidth: 1.5))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !held { held = true; onDown() } }
                    .onEnded { _ in held = false; onUp() }
            )
            .accessibilityLabel(label)
    }
}
#endif
