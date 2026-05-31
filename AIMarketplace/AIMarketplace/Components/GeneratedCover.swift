import SwiftUI

/// Procedurally generates a premium, abstract cover (Apple-Music-/Spotify-Canvas
/// style) for any title with no supplied artwork: a luminous mesh gradient seeded
/// from the item, soft light blooms, and fine grain. Type drives the colour
/// family (music = violet, novel = warm amber, film = teal/indigo) so books,
/// albums and films read distinctly. Deterministic — a title always renders the
/// same cover. This is the on-device fallback; a real image-gen provider can
/// replace it via `coverImageData` (PosterArt prefers that).
struct GeneratedCover: View {
    let item: MediaItem

    private var seed: Int { abs(item.seed) }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                base
                // Soft luminous blooms add depth and a fluid, lit feel.
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(colors[(i * 3 + 2) % colors.count])
                        .frame(width: s * (0.7 + frac(40 + i) * 0.5))
                        .blur(radius: s * 0.26)
                        .offset(x: (frac(50 + i) - 0.5) * geo.size.width,
                                y: (frac(60 + i) - 0.5) * geo.size.height)
                        .blendMode(.screen)
                        .opacity(0.55)
                }
                // Top-left key light + bottom vignette for cinematic depth.
                RadialGradient(colors: [.white.opacity(0.20), .clear],
                               center: .topLeading, startRadius: 0, endRadius: s * 1.15)
                    .blendMode(.softLight)
                RadialGradient(colors: [.clear, .black.opacity(0.40)],
                               center: .center, startRadius: s * 0.35, endRadius: s * 1.1)
                grain(s: s)
            }
            .drawingGroup() // flatten the blends/blurs into one layer (perf + correctness)
        }
    }

    // MARK: Mesh base

    @ViewBuilder private var base: some View {
        if #available(iOS 18.0, *) {
            MeshGradient(width: 3, height: 3, points: meshPoints, colors: colors)
        } else {
            LinearGradient(colors: [colors[0], colors[4], colors[8]],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Seeded colour family

    /// (base hue, hue spread) per media type.
    private var family: (base: Double, spread: Double) {
        switch item.type {
        case .music: return (0.74, 0.20)   // violet → magenta → blue
        case .novel: return (0.07, 0.12)   // amber → gold → rust
        case .movie: return (0.55, 0.18)   // teal → cyan → indigo
        }
    }

    /// Nine luminous colours for the 3×3 mesh, seeded so each title differs
    /// within its family. The centre cell is brightened into a focal glow.
    private var colors: [Color] {
        let h0 = family.base + (frac(99) - 0.5) * 0.12
        return (0..<9).map { i in
            let r1 = frac(i * 3 + 1), r2 = frac(i * 3 + 2), r3 = frac(i * 3 + 3)
            let hue = wrap(h0 + (r1 - 0.5) * family.spread)
            let sat = 0.58 + r2 * 0.38
            let focal = (i == 4) ? 0.22 : 0.0
            let bri = min(0.92, 0.26 + r3 * 0.50 + focal)
            return Color(hue: hue, saturation: sat, brightness: bri)
        }
    }

    /// Corners pinned for full coverage; inner points jittered for organic flow.
    private var meshPoints: [SIMD2<Float>] {
        func j(_ n: Int, _ c: Float) -> Float { c + Float(frac(n) - 0.5) * 0.22 }
        return [
            SIMD2(0, 0),            SIMD2(0.5, 0),          SIMD2(1, 0),
            SIMD2(0, 0.5),          SIMD2(j(11, 0.5), j(12, 0.5)), SIMD2(1, 0.5),
            SIMD2(0, 1),            SIMD2(0.5, 1),          SIMD2(1, 1)
        ]
    }

    // MARK: Grain

    private func grain(s: CGFloat) -> some View {
        Canvas { ctx, size in
            var v = UInt64(truncatingIfNeeded: seed) | 1
            let count = 360
            for _ in 0..<count {
                v ^= v << 13; v ^= v >> 7; v ^= v << 17 // xorshift
                let x = Double(v % 1000) / 1000 * size.width
                let y = Double((v >> 10) % 1000) / 1000 * size.height
                let a = 0.04 + Double((v >> 20) % 100) / 100 * 0.06
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.1, height: 1.1)),
                         with: .color(.white.opacity(a)))
            }
        }
        .blendMode(.overlay)
        .opacity(0.5)
    }

    // MARK: Seeded helpers

    /// Deterministic fractional pseudo-random in 0..<1 from the seed and an index.
    private func frac(_ n: Int) -> Double {
        let x = sin(Double(seed &* 127 &+ n &* 311) * 0.013) * 43758.5453
        return x - x.rounded(.down)
    }

    private func wrap(_ h: Double) -> Double {
        let r = h.truncatingRemainder(dividingBy: 1)
        return r < 0 ? r + 1 : r
    }
}
