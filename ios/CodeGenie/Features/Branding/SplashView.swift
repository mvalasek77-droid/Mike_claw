import SwiftUI

/// First view the user sees on cold start. Shows the CodeGenie mark for
/// ~1.2 seconds while we hydrate `AppSession` from disk, then fades to
/// the real root.
struct SplashView: View {
    var onFinish: () -> Void

    @State private var revealed: Bool = false
    @State private var fading: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 16) {
                CodeGenieLogo(size: 132, animate: !reduceMotion)
                    .scaleEffect(revealed ? 1.0 : 0.85)
                    .opacity(revealed ? 1 : 0)
                    .blur(radius: revealed ? 0 : 6)
                Text("CodeGenie")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 8)
                Text("Ship from your pocket.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("CodeGenie. Ship from your pocket.")
        }
        .opacity(fading ? 0 : 1)
        .task {
            // Honour Reduce Motion: snap visible immediately, hold one
            // beat for legibility, then fade. Same total duration so
            // anything chained off splash continues to time correctly.
            if reduceMotion {
                revealed = true
                try? await Task.sleep(nanoseconds: 800_000_000)
                fading = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { revealed = true }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(.easeIn(duration: 0.45)) { fading = true }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            onFinish()
        }
    }
}

#Preview { SplashView { } }
