#if os(watchOS)
import SwiftUI
import SpriteKit

/// Hosts the SpriteKit scene and pipes the Digital Crown into it. The Crown is
/// the only analog input watchOS gives third-party apps, so it drives the
/// special-meter charge dial.
struct GameView: View {
    @State private var crownValue: Double = 0
    @State private var lastCrown: Double = 0
    @State private var dragStart: Date?
    @FocusState private var focused: Bool

    private let scene: GameScene = {
        let s = GameScene()
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
            .focusable(true)
            .focused($focused)
            .digitalCrownRotation(
                $crownValue,
                from: -1_000_000, through: 1_000_000,
                by: 0.01, sensitivity: .medium,
                isContinuous: true, isHapticFeedbackEnabled: false
            )
            .onChange(of: crownValue) { _, newValue in
                let delta = newValue - lastCrown
                lastCrown = newValue
                scene.feedCrown(delta: CGFloat(delta))
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { _ in
                        if dragStart == nil {
                            dragStart = Date()
                            scene.touchDown()
                        }
                    }
                    .onEnded { value in
                        let held = dragStart.map { Date().timeIntervalSince($0) } ?? 0
                        scene.touchUp(translation: value.translation,
                                      startLocation: value.startLocation,
                                      held: held)
                        dragStart = nil
                    }
            )
            .onAppear { focused = true }
    }
}

#Preview {
    GameView()
}
#endif
