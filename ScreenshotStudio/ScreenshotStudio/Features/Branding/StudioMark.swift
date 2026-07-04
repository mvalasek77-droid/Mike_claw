import SwiftUI

/// The Screenshot Studio glyph: a phone outline whose screen frames a crop
/// reticle — "raw screenshot → framed, store-ready shot" in one mark. Drawn
/// in pure SwiftUI so it stays crisp at every size and adapts to dark mode.
struct StudioMark: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LiquidGlass.auroraGradient)
                .shadow(color: LiquidGlass.accent.opacity(0.5), radius: size * 0.18, y: size * 0.06)

            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: size * 0.012)

            // Phone screen
            RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                .fill(.black.opacity(0.32))
                .frame(width: size * 0.5, height: size * 0.62)
                .overlay(
                    // Crop reticle corners
                    CropReticle(thickness: size * 0.03, length: size * 0.14)
                        .stroke(.white, style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round))
                        .padding(size * 0.1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                        .strokeBorder(.white.opacity(0.5), lineWidth: size * 0.012)
                )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Four L-shaped corner marks forming a crop/framing reticle.
private struct CropReticle: Shape {
    var thickness: CGFloat
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let l = length
        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        // Top-right
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}

/// The wordmark used on the splash and onboarding hero.
struct StudioWordmark: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Screenshot Studio")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .auroraStyle()
            Text("Store-ready screenshots, done right")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
        }
        .multilineTextAlignment(.center)
    }
}
