#if os(watchOS)
import SwiftUI
import SpriteKit

/// Hosts a single match's `FightScene` and pipes the Digital Crown + drag
/// gestures into it. Recreated per fight via `.id(...)` from the parent.
struct FightView: View {
    @State private var crownValue = 0.0
    @State private var lastCrown = 0.0
    @State private var dragStart: Date?
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

            // Always-available exit — no mode (esp. endless Training) can soft-lock.
            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .padding(.top, 2)
            .accessibilityLabel("Quit match")
        }
        .onAppear { focused = true }
    }
}
#endif
