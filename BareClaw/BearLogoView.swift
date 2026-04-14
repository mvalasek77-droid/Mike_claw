import SwiftUI

// MARK: - BearLogoView
//
// Refined geometric bear head. Scales 24 pt → 512 pt.
// Design: warm golden fur, expressive eyes, rose blush, gentle smile.

struct BearLogoView: View {
    var size: CGFloat = 64
    var showBackground: Bool = true

    var body: some View {
        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#1C2438"), Color(hex: "#0D1117")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .shadow(color: Color(hex: "#FF9F0A").opacity(0.25),
                            radius: size * 0.14, y: size * 0.05)
            }
            Canvas { ctx, cs in drawBear(ctx: ctx, size: cs) }
                .frame(width: size * 0.88, height: size * 0.88)
        }
        .frame(width: size, height: size)
    }

    private func drawBear(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height

        let furGrad = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: Color(hex: "#F0B050"), location: 0.0),
                .init(color: Color(hex: "#D8882C"), location: 0.55),
                .init(color: Color(hex: "#B86818"), location: 1.0)
            ]),
            startPoint: CGPoint(x: w * 0.20, y: 0),
            endPoint:   CGPoint(x: w * 0.80, y: h)
        )

        // Ears
        let earR = w * 0.195
        for (ex, ey): (CGFloat, CGFloat) in [(w*0.13, h*0.045), (w*0.675, h*0.045)] {
            ctx.fill(Path(ellipseIn: CGRect(x: ex, y: ey, width: earR*2, height: earR*2)),
                     with: furGrad)
            let iR = earR * 0.58
            ctx.fill(Path(ellipseIn: CGRect(x: ex + (earR - iR), y: ey + (earR - iR) + earR*0.08,
                                             width: iR*2, height: iR*2)),
                     with: .color(Color(hex: "#F0A0A8")))
        }

        // Face
        let fR = w * 0.415, fX = w * 0.5 - fR, fY = h * 0.17
        ctx.fill(Path(ellipseIn: CGRect(x: fX, y: fY, width: fR*2, height: fR*2)),
                 with: furGrad)

        // Snout
        let sW = fR * 0.72, sH = fR * 0.44
        let sX = w/2 - sW/2, sY = h * 0.575
        ctx.fill(Path(ellipseIn: CGRect(x: sX, y: sY, width: sW, height: sH)),
                 with: .color(Color(hex: "#F5DFA8")))

        // Blush
        let bR = fR * 0.28, bY = h * 0.548
        for bX: CGFloat in [w*0.155, w*0.645] {
            ctx.fill(Path(ellipseIn: CGRect(x: bX, y: bY, width: bR*2, height: bR*0.70)),
                     with: .color(Color(hex: "#F07080").opacity(0.28)))
        }

        // Eyes
        let eW = fR * 0.30, eH = eW * 1.12, eY = h * 0.388
        for eX: CGFloat in [w*0.285 - eW/2, w*0.715 - eW/2] {
            ctx.fill(Path(ellipseIn: CGRect(x: eX - eW*0.04, y: eY - eH*0.04,
                                             width: eW*1.08, height: eH*1.08)),
                     with: .color(.white))
            let irisGrad = GraphicsContext.Shading.radialGradient(
                Gradient(colors: [Color(hex: "#5C3010"), Color(hex: "#2A1006")]),
                center: CGPoint(x: eX + eW/2, y: eY + eH*0.46),
                startRadius: 0, endRadius: eW * 0.50)
            ctx.fill(Path(ellipseIn: CGRect(x: eX, y: eY, width: eW, height: eH)),
                     with: irisGrad)
            let pW = eW * 0.55, pH = eH * 0.62
            ctx.fill(Path(ellipseIn: CGRect(x: eX + (eW-pW)/2, y: eY + (eH-pH)/2,
                                             width: pW, height: pH)),
                     with: .color(Color(hex: "#0E0606")))
            // sparkle
            let spk = eW * 0.28
            ctx.fill(Path(ellipseIn: CGRect(x: eX + eW*0.55, y: eY + eH*0.10,
                                             width: spk, height: spk)),
                     with: .color(.white.opacity(0.85)))
            ctx.fill(Path(ellipseIn: CGRect(x: eX + eW*0.25, y: eY + eH*0.52,
                                             width: spk*0.44, height: spk*0.44)),
                     with: .color(.white.opacity(0.48)))
        }

        // Nose
        let nW = sW * 0.32, nH = nW * 0.58
        ctx.fill(Path(ellipseIn: CGRect(x: w/2 - nW/2, y: sY + sH*0.13,
                                         width: nW, height: nH)),
                 with: .color(Color(hex: "#200C04")))

        // Smile
        var smile = Path()
        for sign: CGFloat in [-1, 1] {
            smile.move(to: CGPoint(x: w/2 + sign * nW*0.48, y: sY + sH*0.40))
            smile.addCurve(
                to:       CGPoint(x: w/2 + sign * sW*0.28, y: sY + sH*0.72),
                control1: CGPoint(x: w/2 + sign * nW*0.58, y: sY + sH*0.60),
                control2: CGPoint(x: w/2 + sign * sW*0.22, y: sY + sH*0.60)
            )
        }
        ctx.stroke(smile, with: .color(Color(hex: "#200C04")),
                   style: StrokeStyle(lineWidth: w * 0.024, lineCap: .round))
    }
}

// MARK: - BearBadgeView
//
// Circular Starbucks-siren-style badge. Dark forest-green circle,
// gold outer ring, "BARECLAW" arced across the top, bear face centred.
// Use on the home screen or splash as the primary brand mark.

struct BearBadgeView: View {
    var size: CGFloat = 120

    private let forest = Color(hex: "#1E3932")
    private let gold   = Color(hex: "#CBA258")

    var body: some View {
        ZStack {
            // ── Background circle ──────────────────────────────────────
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#2A4A42"), forest],
                        center: .init(x: 0.42, y: 0.36),
                        startRadius: size * 0.05,
                        endRadius:   size * 0.52
                    )
                )

            // ── Outer gold ring ────────────────────────────────────────
            Circle()
                .strokeBorder(gold, lineWidth: size * 0.022)

            // ── Inner ring (subtle) ────────────────────────────────────
            Circle()
                .strokeBorder(gold.opacity(0.35), lineWidth: size * 0.010)
                .padding(size * 0.088)

            // ── Decorative side stars ──────────────────────────────────
            ForEach([(-1.0, 1.0), (1.0, 1.0)], id: \.0) { (sx, _) in
                Text("✦")
                    .font(.system(size: size * 0.075, weight: .black))
                    .foregroundColor(gold.opacity(0.75))
                    .offset(x: sx * size * 0.34, y: -size * 0.26)
            }

            // ── "BARECLAW" arc across the top ─────────────────────────
            arcText("BARECLAW",
                    radius:   size * 0.355,
                    spanDeg:  148,
                    centerDeg: -90,
                    fontSize: size * 0.092)

            // ── Bear face ──────────────────────────────────────────────
            BearLogoView(size: size * 0.56, showBackground: false)
                .offset(y: size * 0.05)

            // ── Bottom paw print dividers ──────────────────────────────
            HStack(spacing: size * 0.048) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(gold.opacity(0.55))
                        .frame(width: size * 0.030, height: size * 0.030)
                }
            }
            .offset(y: size * 0.38)
        }
        .frame(width: size, height: size)
        .shadow(color: forest.opacity(0.50), radius: size * 0.12, y: size * 0.04)
    }

    /// Renders each character of `text` along a circular arc.
    private func arcText(_ text: String,
                         radius: CGFloat,
                         spanDeg: Double,
                         centerDeg: Double,
                         fontSize: CGFloat) -> some View {
        let chars = Array(text)
        let half  = spanDeg / 2
        let step  = chars.count > 1 ? spanDeg / Double(chars.count - 1) : 0
        return ZStack {
            ForEach(0..<chars.count, id: \.self) { i in
                let deg = centerDeg - half + step * Double(i)
                Text(String(chars[i]))
                    .font(.system(size: fontSize, weight: .black, design: .rounded))
                    .foregroundColor(gold)
                    .kerning(0.5)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(deg + 90))
            }
        }
    }
}

// MARK: - BearIconView
//
// App icon: badge logo on a deep forest-green rounded square.
// Render at 1024×1024 and export to Assets.xcassets.

struct BearIconView: View {
    var size: CGFloat = 1024

    var body: some View {
        ZStack {
            // Rounded-square background — deep forest green
            RoundedRectangle(cornerRadius: size * 0.2237)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#1E3932"), Color(hex: "#0C1E18")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            // Warm gold glow behind the badge
            RadialGradient(
                colors: [Color(hex: "#CBA258").opacity(0.18), .clear],
                center: .center,
                startRadius: 0, endRadius: size * 0.44
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237))

            // Badge — the main icon element
            BearBadgeView(size: size * 0.80)
        }
        .frame(width: size, height: size)
    }

    // drawPaw is kept below for reference / alternative icon builds.
    @available(*, deprecated, message: "Not used in current icon design.")
    private func _drawPaw_unused(ctx: GraphicsContext, size: CGSize) {}

}

// MARK: - Previews

#if DEBUG
#Preview("Badge — sizes") {
    HStack(spacing: 24) {
        BearBadgeView(size: 80)
        BearBadgeView(size: 120)
        BearBadgeView(size: 180)
    }
    .padding(32)
    .background(Color(hex: "#F2F0EB"))
}

#Preview("Badge — dark bg") {
    BearBadgeView(size: 200)
        .padding(40)
        .background(Color(hex: "#0D1117"))
}

#Preview("Bear logo sizes") {
    HStack(spacing: 16) {
        ForEach([24, 44, 64, 96, 128], id: \.self) { sz in
            BearLogoView(size: CGFloat(sz))
        }
    }
    .padding(24)
    .background(Color(hex: "#0D1117"))
}

#Preview("App icon") {
    HStack(spacing: 20) {
        BearIconView(size: 120)
        BearIconView(size: 200)
    }
    .padding(28)
    .background(Color(hex: "#F2F0EB"))
}
#endif
