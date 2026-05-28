import SwiftUI

/// Procedurally generates a distinct, type-appropriate cover (album cover, book
/// cover, film poster) for any title that has no supplied artwork. Everything is
/// seeded from the item, so a title always renders the same cover. One of
/// several background templates is chosen per title for variety.
///
/// This is the on-device fallback; a real image-generation provider can replace
/// it later by supplying `coverImageData` on the item (PosterArt prefers that).
struct GeneratedCover: View {
    let item: MediaItem

    private var seed: Int { abs(item.seed) }
    private var template: Int { seed % 5 }

    private var palette: (base: Color, mid: Color, accent: Color) {
        let hue = Double(seed % 360) / 360.0
        let base = Color(hue: hue, saturation: 0.55, brightness: 0.30)
        let mid = Color(hue: (hue + 0.07).truncatingRemainder(dividingBy: 1), saturation: 0.78, brightness: 0.12)
        // Lean on the media-type accent so books/albums/films read differently.
        let accent = (seed / 7) % 2 == 0 ? item.type.accent
            : Color(hue: (hue + 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 0.95)
        return (base, mid, accent)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let s = min(w, h)
            ZStack {
                LinearGradient(colors: [palette.base, palette.mid],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                motif(w: w, h: h, s: s)
                emblem(s: s, w: w, h: h)
                // Subtle vignette + film grain-ish top light for depth.
                RadialGradient(colors: [.white.opacity(0.10), .clear],
                               center: .topLeading, startRadius: 0, endRadius: s * 1.2)
            }
        }
    }

    // MARK: Background templates

    @ViewBuilder
    private func motif(w: CGFloat, h: CGFloat, s: CGFloat) -> some View {
        switch template {
        case 0:
            // Soft orbs (atmospheric).
            ZStack {
                Circle().fill(palette.accent.opacity(0.55)).frame(width: w * 0.95).blur(radius: 46)
                    .offset(x: CGFloat(seed % 60) - 30, y: -h * 0.30)
                Circle().fill(.white.opacity(0.08)).frame(width: w * 0.6).blur(radius: 34)
                    .offset(x: w * 0.30, y: h * 0.32)
            }
        case 1:
            // Concentric rings (vinyl / target).
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    Circle().strokeBorder(palette.accent.opacity(0.5 - Double(i) * 0.06),
                                          lineWidth: s * 0.02)
                        .frame(width: s * (0.35 + CGFloat(i) * 0.22))
                }
            }
            .offset(y: -h * 0.05)
        case 2:
            // Vertical bars (modernist).
            HStack(spacing: w * 0.03) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i % 2 == 0 ? palette.accent.opacity(0.65) : .white.opacity(0.06))
                        .frame(width: w * (0.06 + CGFloat((seed >> (i + 1)) % 5) * 0.02))
                }
            }
            .rotationEffect(.degrees(8))
            .frame(maxWidth: .infinity, alignment: .leading)
        case 3:
            // Big rotated shapes (poster-graphic).
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.1).fill(palette.accent.opacity(0.6))
                    .frame(width: s * 0.7, height: s * 0.7).rotationEffect(.degrees(Double(seed % 40) - 20))
                    .offset(x: -w * 0.15, y: -h * 0.1).blur(radius: 2)
                Circle().fill(.white.opacity(0.07)).frame(width: s * 0.5).offset(x: w * 0.25, y: h * 0.2)
            }
        default:
            // Halftone dot grid.
            Canvas { ctx, size in
                let step = size.width / 9
                for x in stride(from: step / 2, to: size.width, by: step) {
                    for y in stride(from: step / 2, to: size.height, by: step) {
                        let r = (step / 2) * (0.2 + 0.8 * (1 - y / size.height))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r/2, y: y - r/2, width: r, height: r)),
                                 with: .color(palette.accent.opacity(0.35)))
                    }
                }
            }
        }
    }

    // MARK: Type emblem

    @ViewBuilder
    private func emblem(s: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        switch item.type {
        case .music:
            // Vinyl record disc.
            ZStack {
                Circle().fill(.black.opacity(0.35)).frame(width: s * 0.42)
                Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1).frame(width: s * 0.30)
                Circle().fill(palette.accent.opacity(0.9)).frame(width: s * 0.10)
            }
            .offset(y: -h * 0.06)
        case .novel:
            // Faint serif initial — book-cover feel.
            Text(String(item.title.first ?? "A"))
                .font(.system(size: s * 0.6, weight: .black, design: .serif))
                .foregroundStyle(.white.opacity(0.12))
        case .movie:
            // Cinematic glyph.
            Image(systemName: "film.fill")
                .font(.system(size: s * 0.42, weight: .black))
                .foregroundStyle(.white.opacity(0.13))
                .rotationEffect(.degrees(-6))
        }
    }
}
