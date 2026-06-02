import SwiftUI

/// Animated circular gauge for the AI Editor's overall score, with the 85%
/// commercial bar drawn as a tick on the track.
struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 150
    var threshold: Int = AIReviewResult.threshold

    @State private var animated: CGFloat = 0

    private var color: Color {
        score >= threshold ? Theme.success : Theme.warning
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: size * 0.09)

            Circle()
                .trim(from: 0, to: animated)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.6), color], center: .center),
                    style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // 85% commercial-bar tick.
            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 2, height: size * 0.12)
                .offset(y: -size / 2 + size * 0.045)
                .rotationEffect(.degrees(Double(threshold) / 100 * 360))

            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text("/ 100")
                    .font(.system(size: size * 0.10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            Motion.run(.easeOut(duration: 1.0)) { animated = CGFloat(score) / 100 }
        }
        // VoiceOver should announce the verdict, not "circle. text 85. text /
        // 100." Treat the ring as one element with a meaningful label.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("AI Editor score \(score) out of 100, bar is \(threshold)"))
        .accessibilityValue(Text(score >= threshold ? "Approved" : "Rejected"))
    }
}
