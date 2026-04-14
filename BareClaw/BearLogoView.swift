import SwiftUI

// MARK: - BearLogoView
//
// Emoji-style cute bear head — round, warm, expressive.
// Inspired by the 🐻 bear emoji but distinctively BareClaw.
// Scales cleanly from 24 pt → 512 pt.

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
                    .shadow(color: Color(hex: "#FF9F0A").opacity(0.22),
                            radius: size * 0.14, y: size * 0.05)
            }
            Canvas { ctx, cs in drawBear(ctx: ctx, size: cs) }
                .frame(width: size * 0.88, height: size * 0.88)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Emoji-style bear drawing

    private func drawBear(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height

        // ── Palette ──────────────────────────────────────────────────────
        let furDark  = Color(hex: "#6B3F1F")   // deep brown (ears, shadow edge)
        let furMid   = Color(hex: "#9B5E2A")   // main face fur
        let furLight = Color(hex: "#C2843E")   // warm highlight on top of head
        let muzzle   = Color(hex: "#D4A574")   // cream muzzle area
        let nose     = Color(hex: "#1A0800")   // near-black nose
        let cheek    = Color(hex: "#E87878")   // rosy blush
        let earPink  = Color(hex: "#F5A0B0")   // inner ear
        let eyeDark  = Color(hex: "#120600")   // iris / pupil
        let shine    = Color.white

        // Face radial gradient — warm emoji-face feel
        let faceGrad = GraphicsContext.Shading.radialGradient(
            Gradient(stops: [
                .init(color: furLight, location: 0.00),
                .init(color: furMid,   location: 0.48),
                .init(color: furDark,  location: 1.00)
            ]),
            center: CGPoint(x: w * 0.46, y: h * 0.37),
            startRadius: w * 0.04,
            endRadius:   w * 0.53
        )

        // ── Ears (drawn first — face overlaps them slightly) ──────────
        let earR = w * 0.215
        for (ex, ey): (CGFloat, CGFloat) in [(w * 0.215, h * 0.185), (w * 0.785, h * 0.185)] {
            ctx.fill(
                Path(ellipseIn: CGRect(x: ex - earR, y: ey - earR * 0.90,
                                       width: earR * 2, height: earR * 1.80)),
                with: .color(furDark)
            )
            let iR = earR * 0.60
            ctx.fill(
                Path(ellipseIn: CGRect(x: ex - iR, y: ey - iR * 0.80,
                                       width: iR * 2, height: iR * 1.60)),
                with: .color(earPink)
            )
        }

        // ── Face (round, slightly taller than wide — emoji proportions) ──
        let fR = w * 0.415
        let fCX = w * 0.5, fCY = h * 0.495
        ctx.fill(
            Path(ellipseIn: CGRect(x: fCX - fR, y: fCY - fR * 0.96,
                                   width: fR * 2, height: fR * 1.92)),
            with: faceGrad
        )

        // ── Muzzle (cream oval, lower half of face) ───────────────────
        let mW = fR * 0.76, mH = fR * 0.50
        let mX = w / 2 - mW / 2, mY = h * 0.562
        ctx.fill(
            Path(ellipseIn: CGRect(x: mX, y: mY, width: mW, height: mH)),
            with: .color(muzzle)
        )

        // ── Cheeks (rosy, translucent) ────────────────────────────────
        let ckR = fR * 0.25
        for cx: CGFloat in [w * 0.285, w * 0.715] {
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - ckR, y: h * 0.535,
                                       width: ckR * 2, height: ckR * 1.20)),
                with: .color(cheek.opacity(0.40))
            )
        }

        // ── Eyes (big round — the signature emoji look) ───────────────
        let eR = fR * 0.155
        for eCX: CGFloat in [w * 0.368, w * 0.632] {
            let eCY = h * 0.432

            // Sclera — white, slightly oval
            ctx.fill(
                Path(ellipseIn: CGRect(x: eCX - eR * 1.15, y: eCY - eR * 1.26,
                                       width: eR * 2.30, height: eR * 2.52)),
                with: .color(shine)
            )

            // Iris + pupil (single dark circle for emoji simplicity)
            ctx.fill(
                Path(ellipseIn: CGRect(x: eCX - eR, y: eCY - eR,
                                       width: eR * 2, height: eR * 2)),
                with: .color(eyeDark)
            )

            // Primary shine dot
            let sp = eR * 0.50
            ctx.fill(
                Path(ellipseIn: CGRect(x: eCX + eR * 0.22, y: eCY - eR * 0.60,
                                       width: sp, height: sp)),
                with: .color(shine.opacity(0.94))
            )

            // Tiny secondary shine
            let sp2 = eR * 0.25
            ctx.fill(
                Path(ellipseIn: CGRect(x: eCX - eR * 0.52, y: eCY + eR * 0.28,
                                       width: sp2, height: sp2)),
                with: .color(shine.opacity(0.48))
            )
        }

        // ── Nose (small dark rounded oval at top of muzzle) ──────────
        let nW = mW * 0.30, nH = nW * 0.66
        ctx.fill(
            Path(ellipseIn: CGRect(x: w / 2 - nW / 2, y: mY + mH * 0.09,
                                   width: nW, height: nH)),
            with: .color(nose)
        )

        // ── Smile (gentle Bézier arc) ─────────────────────────────────
        var smile = Path()
        let smY = mY + mH * 0.42
        smile.move(   to: CGPoint(x: w / 2 - nW * 0.54, y: smY))
        smile.addCurve(
            to:       CGPoint(x: w / 2 + nW * 0.54, y: smY),
            control1: CGPoint(x: w / 2 - nW * 0.16, y: smY + nH * 1.10),
            control2: CGPoint(x: w / 2 + nW * 0.16, y: smY + nH * 1.10)
        )
        ctx.stroke(smile, with: .color(nose),
                   style: StrokeStyle(lineWidth: w * 0.022, lineCap: .round))
    }
}

// MARK: - BearBadgeView
//
// Starbucks-siren-style circular badge.
// Deep forest-green circle, warm gold ring, "BARECLAW" arced at top,
// emoji-style bear face centred.

struct BearBadgeView: View {
    var size: CGFloat = 120

    private let forest = Color(hex: "#1E3932")
    private let gold   = Color(hex: "#CBA258")

    var body: some View {
        ZStack {
            // ── Background disc ────────────────────────────────────────
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#2A5248"), forest],
                        center: .init(x: 0.40, y: 0.34),
                        startRadius: size * 0.04,
                        endRadius:   size * 0.54
                    )
                )

            // ── Outer gold ring ────────────────────────────────────────
            Circle()
                .strokeBorder(gold, lineWidth: size * 0.024)

            // ── Inner accent ring ──────────────────────────────────────
            Circle()
                .strokeBorder(gold.opacity(0.30), lineWidth: size * 0.010)
                .padding(size * 0.090)

            // ── Decorative side stars ──────────────────────────────────
            ForEach([(-1.0, 1.0), (1.0, 1.0)], id: \.0) { (sx, _) in
                Text("✦")
                    .font(.system(size: size * 0.072, weight: .black))
                    .foregroundColor(gold.opacity(0.78))
                    .offset(x: sx * size * 0.335, y: -size * 0.265)
            }

            // ── "BARECLAW" arc ─────────────────────────────────────────
            arcText("BARECLAW",
                    radius:    size * 0.358,
                    spanDeg:   146,
                    centerDeg: -90,
                    fontSize:  size * 0.090)

            // ── Emoji bear face ────────────────────────────────────────
            BearLogoView(size: size * 0.58, showBackground: false)
                .offset(y: size * 0.042)

            // ── Bottom dot dividers ────────────────────────────────────
            HStack(spacing: size * 0.044) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(gold.opacity(0.60))
                        .frame(width: size * 0.028, height: size * 0.028)
                }
            }
            .offset(y: size * 0.382)
        }
        .frame(width: size, height: size)
        .shadow(color: forest.opacity(0.55), radius: size * 0.10, y: size * 0.04)
    }

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
                    .kerning(0.6)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(deg + 90))
            }
        }
    }
}

// MARK: - BearIconView
//
// 1024×1024 app icon: badge on deep forest-green rounded square.
// Render BearIconView(size: 1024) and export to Assets.xcassets.

struct BearIconView: View {
    var size: CGFloat = 1024

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2237)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#1E3932"), Color(hex: "#0C1E18")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            RadialGradient(
                colors: [Color(hex: "#CBA258").opacity(0.16), .clear],
                center: .center,
                startRadius: 0, endRadius: size * 0.44
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237))

            BearBadgeView(size: size * 0.80)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Badge — light bg") {
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

#Preview("Bear logo — sizes") {
    HStack(spacing: 16) {
        ForEach([24, 44, 64, 96, 128], id: \.self) { sz in
            BearLogoView(size: CGFloat(sz))
        }
    }
    .padding(24)
    .background(Color(hex: "#0D1117"))
}

#Preview("Bear logo — bare") {
    BearLogoView(size: 200, showBackground: false)
        .padding(24)
        .background(Color(hex: "#1E3932"))
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
