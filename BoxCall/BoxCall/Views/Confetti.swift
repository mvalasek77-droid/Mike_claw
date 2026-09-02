import SwiftUI

/// Particle burst for big wins. Pure SwiftUI/Canvas, no SpriteKit.
/// Fires once per `trigger` change and cleans itself up.
struct ConfettiBurst: View {
    let trigger: Int
    var duration: TimeInterval = 1.8
    var count: Int = 90

    @State private var particles: [Particle] = []
    @State private var startedAt: Date?

    private struct Particle: Identifiable {
        let id = UUID()
        let angle: Double       // radians
        let speed: Double       // pts/sec
        let spin: Double        // rad/sec
        let size: CGFloat
        let color: Color
        let drag: Double
    }

    var body: some View {
        TimelineView(.animation(paused: startedAt == nil)) { tl in
            Canvas { ctx, size in
                guard let start = startedAt else { return }
                let t = tl.date.timeIntervalSince(start)
                guard t < duration else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.35)
                let gravity = 620.0
                for p in particles {
                    let v = p.speed * exp(-p.drag * t)
                    let x = origin.x + CGFloat(cos(p.angle) * v * t)
                    let y = origin.y + CGFloat(sin(p.angle) * v * t + 0.5 * gravity * t * t)
                    let alpha = max(0, 1 - t / duration)
                    var rect = CGRect(x: x, y: y, width: p.size, height: p.size * 0.45)
                    rect = rect.offsetBy(dx: -p.size / 2, dy: -p.size / 4)
                    let path = Path(roundedRect: rect, cornerRadius: 1)
                    let rotated = path.applying(
                        CGAffineTransform(translationX: x, y: y)
                            .rotated(by: p.spin * t)
                            .translatedBy(x: -x, y: -y))
                    ctx.opacity = alpha
                    ctx.fill(rotated, with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        let palette: [Color] = [Theme.marqueeGold, Theme.bulbGlow, Theme.cream,
                                Theme.bull, Theme.velvetRed, .white]
        particles = (0..<count).map { _ in
            Particle(
                angle: Double.random(in: (-Double.pi * 0.95)...(-Double.pi * 0.05)),
                speed: Double.random(in: 380...760),
                spin: Double.random(in: -8...8),
                size: CGFloat.random(in: 5...10),
                color: palette.randomElement()!,
                drag: Double.random(in: 0.9...1.6)
            )
        }
        startedAt = Date()
        Haptics.won(large: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
            particles = []
            startedAt = nil
        }
    }
}

/// Glowing flame badge for an active weekly streak.
struct StreakFlame: View {
    let weeks: Int
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .foregroundStyle(
                    LinearGradient(colors: [Theme.bulbGlow, Theme.velvetRed],
                                   startPoint: .top, endPoint: .bottom))
                .shadow(color: Theme.bulbGlow.opacity(pulse ? 0.9 : 0.4), radius: pulse ? 8 : 3)
                .scaleEffect(pulse ? 1.12 : 1.0)
            Text("\(weeks)w")
                .font(.caption.weight(.heavy).monospacedDigit())
                .foregroundStyle(Theme.cream)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Theme.velvetRed.opacity(0.35)))
        .overlay(Capsule().stroke(Theme.bulbGlow.opacity(0.5), lineWidth: 1))
        .onAppear { withAnimation(Theme.Motion.breathe) { pulse = weeks > 0 } }
        .accessibilityLabel("\(weeks)-week winning streak")
    }
}
