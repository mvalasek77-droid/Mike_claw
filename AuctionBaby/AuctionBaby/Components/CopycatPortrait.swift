import SwiftUI
import UIKit

/// The AI "Copycat" lure portrait: a full-figure glamour illustration — a
/// fashion-croquis silhouette styled per ``CopycatStyle`` (bikini for poolside
/// and beach, crop top + leggings for yoga, a bodycon dress for glam), with
/// glossy synthetic skin-sheen, flowing hair, drifting bloom, a sweeping
/// holo-shine and sparkles. Deliberately gorgeous and deliberately synthetic:
/// the "AI · Copycat" disclosure is baked into the image, because bidding on
/// one is a disclosed, score-dropping part of the game.
///
/// Everything is vector (no photography) at an editorial-illustration level of
/// abstraction, so the lure reads 11/10 while staying App-Store-safe. All
/// animation is `TimelineView`-driven and goes static under Reduce Motion.
struct CopycatPortrait: View {
    let name: String
    var hue: Double = 0.92
    var style: CopycatStyle = .glam
    var corner: CGFloat = Theme.cornerL
    var showWatermark: Bool = true
    var sparkleCount: Int = 8

    private var reduceMotion: Bool { Motion.prefersReducedMotion }

    // Deterministic sparkle field so twinkles don't jump between frames.
    private var sparkles: [Sparkle] {
        var rng = SeededRNG(seed: UInt64(abs(name.hashValue)) &+ 11)
        return (0..<sparkleCount).map { _ in
            Sparkle(x: rng.unit(), y: rng.unit() * 0.85,
                    size: 0.035 + rng.unit() * 0.06,
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
                    figure(size: geo.size)
                    holoSheen(t: t, size: geo.size)
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

    // MARK: Backdrop layers

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
        let by = 0.22 + (reduceMotion ? 0 : cos(t * 0.45) * 0.08)
        return RadialGradient(
            colors: [.white.opacity(0.5), style.accent.opacity(0.18), .clear],
            center: UnitPoint(x: bx, y: by),
            startRadius: 0, endRadius: max(size.width, size.height) * 0.7)
        .blendMode(.screen)
    }

    private func holoSheen(t: Double, size: CGSize) -> some View {
        let period = 3.6
        let p = reduceMotion ? 0.35 : (t.truncatingRemainder(dividingBy: period) / period)
        let travel = size.width * 1.6
        return LinearGradient(
            colors: [.clear, .white.opacity(0.0), .white.opacity(0.45), .white.opacity(0.0), .clear],
            startPoint: .top, endPoint: .bottom)
        .frame(width: size.width * 0.4, height: size.height * 2)
        .rotationEffect(.degrees(24))
        .offset(x: -travel * 0.5 + travel * p, y: 0)
        .blendMode(.plusLighter)
        .opacity(0.7)
    }

    // MARK: The figure

    /// Full-figure glamour illustration: hair behind, glossy croquis silhouette,
    /// style-specific outfit blocks masked to the body, rim light on top.
    private func figure(size: CGSize) -> some View {
        let w = size.width, h = size.height

        // Warm, luminous "synthetic glam" skin gradient.
        let skin = LinearGradient(
            colors: [Color(red: 1.00, green: 0.88, blue: 0.76),
                     Color(red: 0.94, green: 0.72, blue: 0.58),
                     Color(red: 0.62, green: 0.38, blue: 0.32)],
            startPoint: .top, endPoint: .bottom)

        let hairColor = LinearGradient(
            colors: [style.accent.opacity(0.95), Color.black.opacity(0.55)],
            startPoint: .top, endPoint: .bottom)

        return ZStack {
            // Flowing hair, behind the body, down past the waist.
            LongHair()
                .fill(hairColor)
                .frame(width: w * 0.62, height: h * 0.62)
                .position(x: w * 0.5, y: h * 0.34)
                .blur(radius: 0.5)
                .shadow(color: style.accent.opacity(0.4), radius: 10)

            // Head — clean croquis oval, no facial detail (elegant, never uncanny).
            Ellipse()
                .fill(skin)
                .frame(width: w * 0.155, height: h * 0.115)
                .position(x: w * 0.5, y: h * 0.135)

            // Body silhouette.
            FemmeFigure()
                .fill(skin)
                .frame(width: w, height: h)
                .overlay(
                    // Rim light down one side — the glossy studio finish.
                    FemmeFigure()
                        .fill(LinearGradient(colors: [.white.opacity(0.55), .clear],
                                             startPoint: .topLeading, endPoint: .center))
                        .frame(width: w, height: h)
                        .blendMode(.plusLighter)
                        .opacity(0.6)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 6)

            // Outfit — colored blocks masked to the body so they always fit.
            outfit(w: w, h: h)

            // Soft center-line shading gives the silhouette dimension.
            FemmeFigure()
                .fill(RadialGradient(colors: [.clear, .black.opacity(0.18)],
                                     center: .center, startRadius: w * 0.05, endRadius: w * 0.45))
                .frame(width: w, height: h)
        }
    }

    /// Style-specific outfit rendered as fabric-colored regions clipped to the
    /// figure: bikini (poolside/beach), crop top + leggings (yoga), bodycon
    /// dress (glam). Swimwear-level coverage everywhere.
    @ViewBuilder
    private func outfit(w: CGFloat, h: CGFloat) -> some View {
        let fabric = LinearGradient(
            colors: [style.accent, style.accent.opacity(0.75), Color.black.opacity(0.35)],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        switch style {
        case .poolside, .beach:
            // Bikini: chest band + hip band, masked to the silhouette.
            bodyBand(fabric, w: w, h: h, yCenter: 0.305, height: 0.055)
            bodyBand(fabric, w: w, h: h, yCenter: 0.525, height: 0.05)
        case .yoga:
            // Crop top + high-waist leggings.
            bodyBand(fabric, w: w, h: h, yCenter: 0.30, height: 0.075)
            bodyBand(fabric, w: w, h: h, yCenter: 0.745, height: 0.50)   // waist-down
        case .glam:
            // Bodycon dress, shoulder to mid-thigh, with a subtle shine.
            bodyBand(fabric, w: w, h: h, yCenter: 0.435, height: 0.36)
            bodyBand(LinearGradient(colors: [.white.opacity(0.35), .clear],
                                    startPoint: .leading, endPoint: .trailing),
                     w: w, h: h, yCenter: 0.435, height: 0.36)
        }
    }

    /// A horizontal fabric region clipped to the figure silhouette.
    private func bodyBand(_ fill: some ShapeStyle, w: CGFloat, h: CGFloat,
                          yCenter: CGFloat, height: CGFloat) -> some View {
        FemmeFigure()
            .fill(fill)
            .frame(width: w, height: h)
            .mask(
                Rectangle()
                    .frame(width: w, height: h * height)
                    .position(x: w * 0.5, y: h * yCenter)
            )
    }

    // MARK: Sparkle / vignette / watermark

    private func sparkleLayer(t: Double, size: CGSize, base: CGFloat) -> some View {
        ZStack {
            ForEach(Array(sparkles.enumerated()), id: \.offset) { _, sp in
                let tw = reduceMotion ? 0.8 : (sin(t * sp.speed + sp.phase) * 0.5 + 0.5)
                Image(systemName: "sparkle")
                    .font(.system(size: base * sp.size, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: style.accent.opacity(0.9), radius: 6)
                    .opacity(0.3 + tw * 0.7)
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
                    Image(systemName: "sparkles").font(.dynamicScaled(9, weight: .black, relativeTo: .caption2))
                    Text("AI · COPYCAT").font(.dynamicScaled(9, weight: .black, design: .rounded, relativeTo: .caption2)).tracking(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.black.opacity(0.45)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.6))
                Spacer()
                Text(style.caption)
                    .font(.dynamicScaled(9, weight: .heavy, design: .rounded, relativeTo: .caption2))
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

// MARK: - Figure shapes (fashion-croquis abstraction)

/// A full-body standing silhouette — neck to ankles, hourglass through the
/// torso, legs together, croquis proportions. Symmetric: the right side is
/// defined and mirrored. All coordinates are fractions of the rect.
struct FemmeFigure: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cx + x * w, y: rect.minY + y * h)
        }

        var p = Path()
        // Right side, top → bottom.
        p.move(to: pt(0.000, 0.185))                                   // base of neck
        p.addQuadCurve(to: pt(0.055, 0.205), control: pt(0.035, 0.185))
        p.addQuadCurve(to: pt(0.150, 0.265), control: pt(0.135, 0.215))  // shoulder
        p.addQuadCurve(to: pt(0.130, 0.335), control: pt(0.155, 0.305))  // upper arm line
        p.addQuadCurve(to: pt(0.082, 0.425), control: pt(0.095, 0.385))  // waist
        p.addQuadCurve(to: pt(0.170, 0.520), control: pt(0.165, 0.455))  // hip
        p.addQuadCurve(to: pt(0.130, 0.640), control: pt(0.175, 0.585))  // outer thigh
        p.addQuadCurve(to: pt(0.085, 0.760), control: pt(0.105, 0.705))  // knee
        p.addQuadCurve(to: pt(0.088, 0.840), control: pt(0.100, 0.800))  // calf
        p.addQuadCurve(to: pt(0.040, 0.980), control: pt(0.055, 0.930))  // ankle
        // Across the bottom.
        p.addLine(to: pt(-0.040, 0.980))
        // Left side, bottom → top (mirror).
        p.addQuadCurve(to: pt(-0.088, 0.840), control: pt(-0.055, 0.930))
        p.addQuadCurve(to: pt(-0.085, 0.760), control: pt(-0.100, 0.800))
        p.addQuadCurve(to: pt(-0.130, 0.640), control: pt(-0.105, 0.705))
        p.addQuadCurve(to: pt(-0.170, 0.520), control: pt(-0.175, 0.585))
        p.addQuadCurve(to: pt(-0.082, 0.425), control: pt(-0.165, 0.455))
        p.addQuadCurve(to: pt(-0.130, 0.335), control: pt(-0.095, 0.385))
        p.addQuadCurve(to: pt(-0.150, 0.265), control: pt(-0.155, 0.305))
        p.addQuadCurve(to: pt(-0.055, 0.205), control: pt(-0.135, 0.215))
        p.addQuadCurve(to: pt(0.000, 0.185), control: pt(-0.035, 0.185))
        p.closeSubpath()
        return p
    }
}

/// Long flowing hair, rendered behind the figure — crown to below the waist,
/// with a soft outward sweep.
struct LongHair: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cx + x * w, y: rect.minY + y * h)
        }
        var p = Path()
        p.move(to: pt(0, 0.02))
        p.addQuadCurve(to: pt(0.30, 0.28), control: pt(0.34, 0.04))
        p.addQuadCurve(to: pt(0.38, 0.72), control: pt(0.30, 0.52))
        p.addQuadCurve(to: pt(0.16, 0.98), control: pt(0.40, 0.94))
        p.addQuadCurve(to: pt(0.00, 0.90), control: pt(0.06, 0.95))
        p.addQuadCurve(to: pt(-0.16, 0.98), control: pt(-0.06, 0.95))
        p.addQuadCurve(to: pt(-0.38, 0.72), control: pt(-0.40, 0.94))
        p.addQuadCurve(to: pt(-0.30, 0.28), control: pt(-0.30, 0.52))
        p.addQuadCurve(to: pt(0, 0.02), control: pt(-0.34, 0.04))
        p.closeSubpath()
        return p
    }
}
