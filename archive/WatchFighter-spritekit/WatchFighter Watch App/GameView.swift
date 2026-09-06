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
    @State private var usePad = GameSettings.controls == .buttons
    @State private var crownMode = GameSettings.controls == .crown
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
            if crownMode { crownStrip }

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

    /// On-screen virtual gamepad: walk D-pad + actions, in two centered rows
    /// lifted clear of the super-meter bar and the round-screen corners.
    private var gamepad: some View {
        VStack {
            Spacer()
            HStack(spacing: 5) {
                HoldButton("◀", onDown: { scene.padMove(-1) }, onUp: { scene.padMove(0) })
                HoldButton("▶", onDown: { scene.padMove(1) }, onUp: { scene.padMove(0) })
                PadButton("↑", tint: .green) { scene.padTap(.jump) }
                HoldButton("BLK", tint: .blue,
                           onDown: { scene.padBlock(true) }, onUp: { scene.padBlock(false) })
            }
            HStack(spacing: 5) {
                PadButton("P", tint: .cyan) { scene.padTap(.lightAttack) }
                PadButton("K", tint: .orange) { scene.padTap(.heavyAttack) }
                PadButton("SP", tint: .yellow) { scene.padTap(.special) }
                PadButton("GR", tint: .purple) { scene.padTap(.grab) }
            }
            .padding(.bottom, 16)
        }
        .ignoresSafeArea()
    }

    /// Crown mode: the Crown walks; these action buttons sit in two centered rows
    /// in the dark ground area (clear of the meter bar and the curved corners).
    private var crownStrip: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                PadButton("P", tint: .cyan) { scene.padTap(.lightAttack) }       // punch
                PadButton("K", tint: .orange) { scene.padTap(.heavyAttack) }     // kick
                PadButton("↑", tint: .green) { scene.padTap(.jump) }             // jump
            }
            HStack(spacing: 6) {
                HoldButton("BLK", tint: .blue,
                           onDown: { scene.padBlock(true) }, onUp: { scene.padBlock(false) })
                PadButton("SP", tint: .yellow) { scene.padTap(.special) }
                PadButton("GR", tint: .purple) { scene.padTap(.grab) }
            }
            .padding(.bottom, 16)
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
