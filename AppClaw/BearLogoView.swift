import SwiftUI

// MARK: - OpenClaw Bear Head Logo
//
// A cute geometric bear head built entirely from SwiftUI Shapes —
// no external assets needed.  Scales cleanly from 24 pt (nav bar icon)
// up to 512 pt (App Store icon).
//
// Colour scheme follows the OpenClaw theme: midnight navy background,
// amber-claw gradient, electric-blue accent eyes.

// MARK: - Bear shape primitives

/// Full bear head silhouette (face + round ears).
struct BearHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()

        // Main circular face
        let faceR = w * 0.42
        let faceC = CGPoint(x: w * 0.50, y: h * 0.54)
        p.addEllipse(in: CGRect(
            x: faceC.x - faceR, y: faceC.y - faceR,
            width: faceR * 2, height: faceR * 2
        ))

        // Left ear
        let earR = w * 0.18
        p.addEllipse(in: CGRect(
            x: w * 0.12, y: h * 0.06,
            width: earR * 2, height: earR * 2
        ))

        // Right ear
        p.addEllipse(in: CGRect(
            x: w * 0.70, y: h * 0.06,
            width: earR * 2, height: earR * 2
        ))

        return p
    }
}

/// Inner ear circles.
struct BearInnerEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let r = w * 0.10

        // Left inner ear
        p.addEllipse(in: CGRect(x: w * 0.18, y: h * 0.12, width: r * 2, height: r * 2))
        // Right inner ear
        p.addEllipse(in: CGRect(x: w * 0.72, y: h * 0.12, width: r * 2, height: r * 2))
        return p
    }
}

/// Snout area — slightly lighter oval below the eyes.
struct BearSnoutShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        let sw = w * 0.32, sh = h * 0.20
        p.addEllipse(in: CGRect(
            x: (w - sw) / 2, y: h * 0.60,
            width: sw, height: sh
        ))
        return p
    }
}

// MARK: - BearLogoView

/// Composited bear head with OpenClaw theming.
/// - Parameters:
///   - size: Bounding square in points (default 64).
///   - showBackground: If true, draws a rounded-rect card background.
struct BearLogoView: View {
    var size: CGFloat = 64
    var showBackground: Bool = true

    var body: some View {
        ZStack {
            // Optional card background
            if showBackground {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#1A2233"), Color.OC.background],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: Color.OC.accent.opacity(0.3), radius: size * 0.12, y: size * 0.04)
            }

            // Bear head silhouette — amber-claw gradient
            BearHeadShape()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#C8862A"), Color(hex: "#FF9F0A"), Color(hex: "#E8A030")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.82, height: size * 0.82)

            // Inner ears — darker amber
            BearInnerEarShape()
                .fill(Color(hex: "#A06820"))
                .frame(width: size * 0.82, height: size * 0.82)

            // Snout — cream
            BearSnoutShape()
                .fill(Color(hex: "#F0D090"))
                .frame(width: size * 0.82, height: size * 0.82)

            // Eyes — electric blue with specular dot
            bearEyes

            // Nose — small dark oval on snout
            Ellipse()
                .fill(Color(hex: "#3A2010"))
                .frame(width: size * 0.10, height: size * 0.065)
                .offset(y: size * 0.185)

            // Subtle "claw mark" overlay — three thin diagonal lines at bottom-right
            if size >= 40 {
                clawMarkOverlay
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Eyes

    @ViewBuilder
    private var bearEyes: some View {
        let eyeR = size * 0.068
        let eyeOffX = size * 0.135
        let eyeOffY = size * 0.04

        ZStack {
            // Left eye white
            Circle().fill(Color.white)
                .frame(width: eyeR * 2.2, height: eyeR * 2.2)
                .offset(x: -eyeOffX, y: -eyeOffY)
            // Left iris — electric blue
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.OC.primary, Color(hex: "#0055CC")],
                        center: .center, startRadius: 0, endRadius: eyeR
                    )
                )
                .frame(width: eyeR * 2, height: eyeR * 2)
                .offset(x: -eyeOffX, y: -eyeOffY)
            // Left specular
            Circle().fill(Color.white.opacity(0.7))
                .frame(width: eyeR * 0.55, height: eyeR * 0.55)
                .offset(x: -eyeOffX + eyeR * 0.35, y: -eyeOffY - eyeR * 0.35)

            // Right eye white
            Circle().fill(Color.white)
                .frame(width: eyeR * 2.2, height: eyeR * 2.2)
                .offset(x: eyeOffX, y: -eyeOffY)
            // Right iris
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.OC.primary, Color(hex: "#0055CC")],
                        center: .center, startRadius: 0, endRadius: eyeR
                    )
                )
                .frame(width: eyeR * 2, height: eyeR * 2)
                .offset(x: eyeOffX, y: -eyeOffY)
            // Right specular
            Circle().fill(Color.white.opacity(0.7))
                .frame(width: eyeR * 0.55, height: eyeR * 0.55)
                .offset(x: eyeOffX + eyeR * 0.35, y: -eyeOffY - eyeR * 0.35)
        }
    }

    // MARK: - Claw mark

    @ViewBuilder
    private var clawMarkOverlay: some View {
        let s = size
        // Bug fix #1: use the Canvas closure's own `canvasSize` instead of the
        // captured `s` — avoids misalignment when layout resolves a different size.
        Canvas { ctx, canvasSize in
            let w = canvasSize.width, h = canvasSize.height
            let offX = w * 0.26
            let offY = h * 0.22
            let len  = h * 0.18
            let gap  = w * 0.055
            for i in 0..<3 {
                let dx = CGFloat(i) * gap
                var line = Path()
                line.move(to:    CGPoint(x: w / 2 + offX + dx,             y: h / 2 + offY))
                line.addLine(to: CGPoint(x: w / 2 + offX + dx + len * 0.5, y: h / 2 + offY + len))
                ctx.stroke(line,
                           with: .color(Color.OC.accent.opacity(0.45)),
                           style: StrokeStyle(lineWidth: w * 0.022, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .blendMode(.overlay)
    }
}

// MARK: - App icon variant (no background card, for Asset Catalog)

struct BearIconView: View {
    var size: CGFloat = 1024
    var body: some View {
        ZStack {
            // Solid background for App Store icon
            RoundedRectangle(cornerRadius: size * 0.2237) // Apple icon corner formula
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#131A25"), Color(hex: "#0D1117")],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            BearLogoView(size: size * 0.75, showBackground: false)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Logo sizes") {
    HStack(spacing: 20) {
        ForEach([24, 44, 64, 96], id: \.self) { sz in
            BearLogoView(size: CGFloat(sz))
        }
    }
    .padding(24)
    .background(Color.OC.background)
}

#Preview("App icon") {
    BearIconView(size: 256)
        .padding(20)
        .background(Color.OC.background)
}
#endif
