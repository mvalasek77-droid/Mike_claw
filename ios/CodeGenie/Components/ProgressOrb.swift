import SwiftUI

/// Animated progress orb used during builds. Has its own life-cycle so we
/// avoid spawning a Timer per consumer — the TimelineView handles the redraw
/// budget for us.
struct ProgressOrb: View {
    var progress: Double            // 0…1
    var label: String
    var subtitle: String? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [LiquidGlass.accentSecondary.opacity(0.55), .clear],
                            center: .center, startRadius: 4, endRadius: 140
                        )
                    )
                    .blur(radius: 18)
                    .scaleEffect(1 + 0.04 * sin(t * 1.5))

                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: max(0.04, progress))
                    .stroke(
                        AngularGradient(
                            colors: [LiquidGlass.accent, LiquidGlass.accentSecondary, LiquidGlass.success, LiquidGlass.accent],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: progress)

                VStack(spacing: 4) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .frame(width: 220, height: 220)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label), \(Int(progress * 100)) percent"))
    }
}
