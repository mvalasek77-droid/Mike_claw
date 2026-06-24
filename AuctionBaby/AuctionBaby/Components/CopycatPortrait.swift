import SwiftUI
import UIKit

/// A deliberately *synthetic* portrait for AI "Copycat" lure profiles. There is
/// no photography here — it's an iridescent, holographic, fashion-illustration
/// figure that reads as gorgeous-but-obviously-generated, with the AI
/// disclosure baked right into the image. Styling cues (poolside / beach / yoga
/// / glam) are carried by palette and a stylised silhouette, never by exposed
/// bodies, so it stays tasteful and App-Store-safe while still being the
/// eye-catching bait the game intends.
///
/// Richly animated via `TimelineView` (drifting bloom, sweeping holo-sheen,
/// twinkling sparkles, hue breathing) — and fully static under Reduce Motion.
struct CopycatPortrait: View {
    let name: String
    var hue: Double = 0.92
    var style: CopycatStyle = .glam
    var corner: CGFloat = Theme.cornerL
    var showWatermark: Bool = true
    var sparkleCount: Int = 7

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    // Deterministic sparkle field so twinkles don't jump between frames.
    private var sparkles: [Sparkle] {
        var rng = SeededRNG(seed: UInt64(abs(name.hashValue)) &+ 11)
        return (0..<sparkleCount).map { _ in
            Sparkle(x: rng.unit(), y: rng.unit() * 0.82,
                    size: 0.04 + rng.unit() * 0.07,
                    speed: 0.6 + rng.unit() * 1.8,
                    phase: rng.unit() * 6.28)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 8.0 : timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                ZStack {
                    backdrop(t: t)
                    bloom(t: t, size: geo.size)
                    holoSheen(t: t, size: geo.size)
                    figure(size: geo.size)
                    sparkleLayer(t: t, size: geo.size, base: s)
                    edgeVignette
                    if showWatermark { watermark }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), style.accent.opacity(0.4), .white.opacity(0.1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
        )
        .accessibilityElement()
        .accessibilityLabel("\(name), AI-generated Copycat profile, \(style.caption)")
    }

    // MARK: Layers

    private func backdrop(t: Double) -> some View {
        let breathe = reduceMotion ? 0 : sin(t * 0.5) * 26
        return LinearGradient(
            colors: style.hues.map { Color(hue: $0, saturation: 0.62, brightness: 0.92) },
            startPoint: .topLeading, endPoint: .bottomTrailing)
        .hueRotation(.degrees(breathe))
        .overlay(
            AngularGradient(
                gradient: Gradient(colors: [style.accent.opacity(0.0), .white.opacity(0.22),
                                            style.accent.opacity(0.0), Theme.copycat.opacity(0.18),
                                            style.accent.opacity(0.0)]),
                center: .center)
            .blendMode(.plusLighter)
            .rotationEffect(.degrees(reduceMotion ? 0 : t * 10))
            .opacity(0.5)
        )
    }

    private func bloom(t: Double, size: CGSize) -> some View {
        let bx = 0.5 + (reduceMotion ? 0 : sin(t * 0.6) * 0.18)
        let by = 0.26 + (reduceMotion ? 0 : cos(t * 0.45) * 0.10)
        return RadialGradient(
            colors: [.white.opacity(0.55), style.accent.opacity(0.18), .clear],
            center: UnitPoint(x: bx, y: by),
            startRadius: 0, endRadius: max(size.width, size.height) * 0.7)
        .blendMode(.screen)
    }

    private func holoSheen(t: Double, size: CGSize) -> some View {
        // A bright diagonal band that sweeps across the portrait on a loop.
        let period = 3.6
        let p = reduceMotion ? 0.35 : (t.truncatingRemainder(dividingBy: period) / period)
        let travel = size.width * 1.6
        return LinearGradient(
            colors: [.clear, .white.opacity(0.0), .white.opacity(0.55), .white.opacity(0.0), .clear],
            startPoint: .top, endPoint: .bottom)
        .frame(width: size.width * 0.4, height: size.height * 2)
        .rotationEffect(.degrees(24))
        .offset(x: -travel * 0.5 + travel * p, y: 0)
        .blendMode(.plusLighter)
        .opacity(0.8)
    }

    private func figure(size: CGSize) -> some View {
        let figW = size.width * 0.78
        let figH = size.height * 0.92
        return ZStack {
            // Hair / aura behind the figure.
            SirenHair()
                .fill(LinearGradient(colors: [style.accent.opacity(0.9), Color.black.opacity(0.35)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: figW * 1.18, height: figH)
                .blur(radius: 1)
            // The figure — head + shoulders, glossy gradient.
            SirenFigure()
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.92), style.accent.opacity(0.85),
                             Color.black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: figW, height: figH)
                .overlay(
                    SirenFigure()
                        .stroke(LinearGradient(colors: [.white.opacity(0.85), .clear],
                                               startPoint: .topLeading, endPoint: .bottom),
                                lineWidth: 1.4)
                        .frame(width: figW, height: figH)
                )
                .shadow(color: style.accent.opacity(0.5), radius: 14, y: 6)
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
    }

    private func sparkleLayer(t: Double, size: CGSize, base: CGFloat) -> some View {
        ZStack {
            ForEach(Array(sparkles.enumerated()), id: \.offset) { _, sp in
                let tw = reduceMotion ? 0.8 : (sin(t * sp.speed + sp.phase) * 0.5 + 0.5)
                Image(systemName: "sparkle")
                    .font(.system(size: base * sp.size, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: style.accent.opacity(0.9), radius: 6)
                    .opacity(0.35 + tw * 0.65)
                    .scaleEffect(0.7 + tw * 0.5)
                    .position(x: sp.x * size.width, y: sp.y * size.height)
                    .blendMode(.plusLighter)
            }
        }
    }

    private var edgeVignette: some View {
        RadialGradient(colors: [.clear, .black.opacity(0.42)],
                       center: .center, startRadius: 60, endRadius: 360)
        .allowsHitTesting(false)
    }

    private var watermark: some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .black))
                    Text("AI · COPYCAT").font(.system(size: 9, weight: .black, design: .rounded)).tracking(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.45)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.6))
                Spacer()
                Text(style.caption)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(style.accent.opacity(0.55)))
            }
            .padding(8)
        }
        .allowsHitTesting(false)
    }
}

private struct Sparkle {
    let x: Double, y: Double, size: Double, speed: Double, phase: Double
}

/// Tiny deterministic PRNG so each Copycat's sparkle field is stable per name.
private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    mutating func unit() -> Double { Double(next() % 10_000) / 10_000.0 }
}

// MARK: - Stylised figure shapes (abstract fashion silhouette — head & shoulders)

/// Elegant head-and-shoulders silhouette, bottom-anchored and centred.
struct SirenFigure: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX
        var p = Path()

        // Head (oval).
        let headCY = rect.minY + h * 0.30
        let headRX = w * 0.16, headRY = h * 0.20
        p.addEllipse(in: CGRect(x: cx - headRX, y: headCY - headRY,
                                width: headRX * 2, height: headRY * 2))

        // Neck + shoulders + bust as one flowing body.
        var body = Path()
        body.move(to: CGPoint(x: cx - w * 0.07, y: headCY + headRY * 0.7))      // neck left
        body.addQuadCurve(to: CGPoint(x: cx - w * 0.40, y: rect.maxY),          // out to L shoulder
                          control: CGPoint(x: cx - w * 0.26, y: headCY + h * 0.20))
        body.addLine(to: CGPoint(x: cx + w * 0.40, y: rect.maxY))               // shoulder line
        body.addQuadCurve(to: CGPoint(x: cx + w * 0.07, y: headCY + headRY * 0.7), // up to neck right
                          control: CGPoint(x: cx + w * 0.26, y: headCY + h * 0.20))
        body.closeSubpath()
        p.addPath(body)
        return p
    }
}

/// Flowing hair / aura behind the figure.
struct SirenHair: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX
        var p = Path()
        p.move(to: CGPoint(x: cx, y: rect.minY + h * 0.06))
        p.addQuadCurve(to: CGPoint(x: cx - w * 0.46, y: rect.minY + h * 0.55),
                       control: CGPoint(x: cx - w * 0.52, y: rect.minY + h * 0.10))
        p.addQuadCurve(to: CGPoint(x: cx - w * 0.18, y: rect.maxY),
                       control: CGPoint(x: cx - w * 0.50, y: rect.maxY - h * 0.10))
        p.addLine(to: CGPoint(x: cx + w * 0.18, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: cx + w * 0.46, y: rect.minY + h * 0.55),
                       control: CGPoint(x: cx + w * 0.50, y: rect.maxY - h * 0.10))
        p.addQuadCurve(to: CGPoint(x: cx, y: rect.minY + h * 0.06),
                       control: CGPoint(x: cx + w * 0.52, y: rect.minY + h * 0.10))
        p.closeSubpath()
        return p
    }
}
