import SwiftUI

/// Brief, tasteful launch reveal. Honours Reduce Motion by skipping the
/// spring and simply holding the final pose.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            StudioMark(size: 116)
                .scaleEffect(appeared ? 1 : 0.82)
                .opacity(appeared ? 1 : 0)
            StudioWordmark()
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
        }
        .onAppear {
            if reduceMotion {
                appeared = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { onFinished() }
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
                Haptics.tap(intensity: 0.5, sharpness: 0.4)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
                    onFinished()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Screenshot Studio")
    }
}
