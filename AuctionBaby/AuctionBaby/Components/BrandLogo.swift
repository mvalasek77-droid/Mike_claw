import SwiftUI

/// The Auction Baby mark: an auctioneer's gavel whose head is a heart, struck
/// on a gold sound-block. Money (gold) meeting desire (the heart shape) — the
/// whole product in one glyph. Pure vector so it scales from a 20pt tab item
/// to the 1024px App Store icon with no raster assets.
struct BrandMark: View {
    var size: CGFloat = 56
    /// When true, renders on its own gallery-black tile (used for the app icon).
    var framed: Bool = false

    var body: some View {
        ZStack {
            if framed {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Color(white: 0.12), Color(white: 0.02)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(
                        RadialGradient(colors: [Theme.gold.opacity(0.28), .clear],
                                       center: .init(x: 0.5, y: 0.25),
                                       startRadius: 0, endRadius: size * 0.7)
                    )
            }
            mark
                .frame(width: size * 0.72, height: size * 0.72)
        }
        .frame(width: size, height: size)
    }

    private var mark: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // Sound block (the base the gavel strikes).
                Capsule()
                    .fill(Theme.goldGradient)
                    .frame(width: s * 0.92, height: s * 0.16)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: s * 0.01))
                    .offset(y: s * 0.40)
                    .shadow(color: Theme.gold.opacity(0.5), radius: s * 0.05, y: s * 0.02)

                // Gavel handle, angled like a downward strike.
                Capsule()
                    .fill(Theme.goldGradient)
                    .frame(width: s * 0.12, height: s * 0.5)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: s * 0.008))
                    .rotationEffect(.degrees(38))
                    .offset(x: s * 0.18, y: s * 0.14)

                // The gavel head — a heart.
                HeartShape()
                    .fill(Theme.roseGradient)
                    .overlay(
                        HeartShape().strokeBorder(.white.opacity(0.35), lineWidth: s * 0.012)
                    )
                    .frame(width: s * 0.5, height: s * 0.46)
                    .rotationEffect(.degrees(38))
                    .offset(x: -s * 0.12, y: -s * 0.16)
                    .shadow(color: Theme.rose.opacity(0.55), radius: s * 0.06, y: s * 0.02)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// A classic two-lobe heart, usable as both a fill and a stroke.
struct HeartShape: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.minX + w * 0.5, y: r.minY + h * 0.96))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.28),
                   control1: CGPoint(x: r.minX + w * 0.16, y: r.minY + h * 0.72),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.52))
        p.addArc(center: CGPoint(x: r.minX + w * 0.25, y: r.minY + h * 0.28),
                 radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addArc(center: CGPoint(x: r.minX + w * 0.75, y: r.minY + h * 0.28),
                 radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addCurve(to: CGPoint(x: r.minX + w * 0.5, y: r.minY + h * 0.96),
                   control1: CGPoint(x: r.maxX, y: r.minY + h * 0.52),
                   control2: CGPoint(x: r.maxX - w * 0.16, y: r.minY + h * 0.72))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var s = self; s.inset += amount; return s
    }
}

/// Wordmark used on the splash and onboarding header.
struct Wordmark: View {
    var size: CGFloat = 30
    var body: some View {
        HStack(spacing: 2) {
            Text("AUCTION")
                .foregroundStyle(Theme.ink)
            Text("BABY")
                .foregroundStyle(Theme.goldGradient)
        }
        .font(.system(size: size, weight: .heavy, design: .serif))
        .tracking(size * 0.04)
        .accessibilityElement()
        .accessibilityLabel("Auction Baby")
    }
}
