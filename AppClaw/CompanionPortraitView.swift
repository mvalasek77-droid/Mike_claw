import SwiftUI

// MARK: - CompanionPortraitView
//
// Fully on-device illustrated portrait for each companion.
// Drawn with SwiftUI Canvas — no image assets required.
// Replaces the generic person.fill placeholder.
//
// Design language: layered gradient bg + hair silhouette + face oval +
// minimal feature hints (eyes, lips). Intentionally illustrative, not
// photo-realistic — same style as Headspace / Calm app characters.

struct CompanionPortraitView: View {
    let companion: CompanionPersonality
    let size: AvatarSize

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, canvasSize in
                drawPortrait(ctx: ctx, size: canvasSize)
            }
        }
    }

    // MARK: - Main draw

    private func drawPortrait(ctx: GraphicsContext, size: CGSize) {
        let cfg = PortraitConfig.for(id: companion.id)
        let w = size.width, h = size.height

        // 1. Background gradient
        let bgRect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(bgRect), with: .linearGradient(
            Gradient(colors: cfg.bgColors),
            startPoint: CGPoint(x: w * 0.3, y: 0),
            endPoint:   CGPoint(x: w * 0.7, y: h)
        ))

        // 2. Shoulders / body block
        let shoulderPath = makeShoulderPath(cfg: cfg, size: size)
        ctx.fill(shoulderPath, with: .color(cfg.clothingColor))

        // 3. Hair behind face
        let hairPath = makeHairPath(cfg: cfg, face: faceRect(size: size), size: size)
        ctx.fill(hairPath, with: .color(cfg.hairColor))

        // Optional second hair layer for volume
        if let hair2 = cfg.hairColor2 {
            let hair2Path = makeHairLayer2(cfg: cfg, face: faceRect(size: size), size: size)
            ctx.fill(hair2Path, with: .color(hair2.opacity(0.6)))
        }

        // 4. Neck
        let face = faceRect(size: size)
        let neckW = face.width * 0.30
        let neckRect = CGRect(
            x: face.midX - neckW / 2,
            y: face.maxY - face.height * 0.04,
            width: neckW,
            height: face.height * 0.18
        )
        ctx.fill(Path(neckRect), with: .color(cfg.skinColor))

        // 5. Face oval
        ctx.fill(Path(ellipseIn: face), with: .color(cfg.skinColor))

        // 6. Subtle facial shading (cheek warmth)
        let cheekSize = face.width * 0.28
        let cheekY = face.minY + face.height * 0.52
        let leftCheek = CGRect(x: face.minX + face.width * 0.06, y: cheekY,
                               width: cheekSize, height: cheekSize * 0.5)
        let rightCheek = CGRect(x: face.maxX - face.width * 0.06 - cheekSize, y: cheekY,
                                width: cheekSize, height: cheekSize * 0.5)
        ctx.fill(Path(ellipseIn: leftCheek),  with: .color(cfg.cheekColor.opacity(0.22)))
        ctx.fill(Path(ellipseIn: rightCheek), with: .color(cfg.cheekColor.opacity(0.22)))

        // 7. Eyes
        let eyeW = face.width * 0.11
        let eyeH = eyeW * 0.62
        let eyeY = face.minY + face.height * 0.40
        let eyeInset = face.width * 0.19
        let leftEye  = CGRect(x: face.midX - eyeInset - eyeW / 2, y: eyeY, width: eyeW, height: eyeH)
        let rightEye = CGRect(x: face.midX + eyeInset - eyeW / 2, y: eyeY, width: eyeW, height: eyeH)
        ctx.fill(Path(ellipseIn: leftEye),  with: .color(cfg.eyeColor))
        ctx.fill(Path(ellipseIn: rightEye), with: .color(cfg.eyeColor))

        // Eye highlights
        let hlSize = eyeW * 0.30
        let leftHL  = CGRect(x: leftEye.minX  + eyeW * 0.55, y: leftEye.minY  + eyeH * 0.15, width: hlSize, height: hlSize)
        let rightHL = CGRect(x: rightEye.minX + eyeW * 0.55, y: rightEye.minY + eyeH * 0.15, width: hlSize, height: hlSize)
        ctx.fill(Path(ellipseIn: leftHL),  with: .color(.white.opacity(0.7)))
        ctx.fill(Path(ellipseIn: rightHL), with: .color(.white.opacity(0.7)))

        // 8. Lips
        let lipW = face.width * 0.30
        let lipH = face.height * 0.075
        let lipY = face.minY + face.height * 0.67
        let lipRect = CGRect(x: face.midX - lipW / 2, y: lipY, width: lipW, height: lipH)
        ctx.fill(Path(ellipseIn: lipRect), with: .color(cfg.lipColor))
        // Upper lip highlight
        let ulipRect = CGRect(x: face.midX - lipW * 0.35, y: lipY,
                              width: lipW * 0.70, height: lipH * 0.45)
        ctx.fill(Path(ellipseIn: ulipRect), with: .color(cfg.lipColor.opacity(0.55)))

        // 9. Name badge at bottom
        // (Skip for .chat size — too small)
        if size.width > 60 {
            let badgeH: CGFloat = 28
            let badgeW: CGFloat = min(w * 0.6, 120)
            let badgeRect = CGRect(x: (w - badgeW) / 2, y: h - badgeH - 10,
                                   width: badgeW, height: badgeH)
            ctx.fill(Path(RoundedRectangle(cornerRadius: 8).path(in: badgeRect)),
                     with: .color(.black.opacity(0.45)))
        }
    }

    // MARK: - Geometry helpers

    private func faceRect(size: CGSize) -> CGRect {
        let w = size.width, h = size.height
        let fW = w * 0.46
        let fH = fW * 1.28
        return CGRect(x: (w - fW) / 2, y: h * 0.18, width: fW, height: fH)
    }

    private func makeShoulderPath(cfg: PortraitConfig, size: CGSize) -> Path {
        let w = size.width, h = size.height
        let face = faceRect(size: size)
        let neckBottom = face.maxY + face.height * 0.14
        let sW = w * cfg.shoulderWidthRatio
        let sL = (w - sW) / 2, sR = sL + sW

        var p = Path()
        p.move(to: CGPoint(x: sL, y: h))
        p.addLine(to: CGPoint(x: sL, y: neckBottom + face.height * 0.12))
        p.addCurve(
            to: CGPoint(x: sR, y: neckBottom + face.height * 0.12),
            control1: CGPoint(x: face.midX - face.width * 0.08, y: neckBottom - face.height * 0.02),
            control2: CGPoint(x: face.midX + face.width * 0.08, y: neckBottom - face.height * 0.02)
        )
        p.addLine(to: CGPoint(x: sR, y: h))
        p.closeSubpath()
        return p
    }

    private func makeHairPath(cfg: PortraitConfig, face: CGRect, size: CGSize) -> Path {
        let h = size.height
        switch cfg.hairStyle {
        case .longWavy:
            return Path(ellipseIn: CGRect(
                x: face.minX - face.width * 0.30,
                y: face.minY - face.height * 0.28,
                width: face.width * 1.60,
                height: h - face.minY + face.height * 0.28
            ))
        case .longStraight:
            return Path(ellipseIn: CGRect(
                x: face.minX - face.width * 0.22,
                y: face.minY - face.height * 0.22,
                width: face.width * 1.44,
                height: h * 0.82 - face.minY
            ))
        case .mediumStraight:
            return Path(ellipseIn: CGRect(
                x: face.minX - face.width * 0.18,
                y: face.minY - face.height * 0.22,
                width: face.width * 1.36,
                height: face.height * 1.20
            ))
        case .mediumCurly:
            return Path(ellipseIn: CGRect(
                x: face.minX - face.width * 0.38,
                y: face.minY - face.height * 0.35,
                width: face.width * 1.76,
                height: face.height * 1.30
            ))
        case .shortWavy:
            return Path(ellipseIn: CGRect(
                x: face.minX - face.width * 0.12,
                y: face.minY - face.height * 0.20,
                width: face.width * 1.24,
                height: face.height * 0.75
            ))
        case .shortClean:
            return Path(ellipseIn: CGRect(
                x: face.minX - face.width * 0.06,
                y: face.minY - face.height * 0.16,
                width: face.width * 1.12,
                height: face.height * 0.58
            ))
        }
    }

    private func makeHairLayer2(cfg: PortraitConfig, face: CGRect, size: CGSize) -> Path {
        // Side volume layer
        Path(ellipseIn: CGRect(
            x: face.minX - face.width * (cfg.hairStyle == .longWavy ? 0.50 : 0.30),
            y: face.midY,
            width: face.width * (cfg.hairStyle == .longWavy ? 0.38 : 0.28),
            height: face.height * 0.80
        ))
    }
}

// MARK: - PortraitConfig

struct PortraitConfig {
    enum HairStyle { case longWavy, longStraight, mediumStraight, mediumCurly, shortWavy, shortClean }

    let bgColors: [Color]
    let hairColor: Color
    let hairColor2: Color?
    let hairStyle: HairStyle
    let skinColor: Color
    let cheekColor: Color
    let clothingColor: Color
    let eyeColor: Color
    let lipColor: Color
    let shoulderWidthRatio: CGFloat  // fraction of canvas width

    static func `for`(id: String) -> PortraitConfig {
        switch id {

        // ── LUNA — old-Hollywood blonde, rose/gold palette ───────────────
        case "luna":
            return PortraitConfig(
                bgColors:  [Color(hex: "#2B0A1E") ?? .black,
                            Color(hex: "#6B1F45") ?? .purple,
                            Color(hex: "#C4607A") ?? .pink],
                hairColor:  Color(hex: "#E8C050") ?? .yellow,
                hairColor2: Color(hex: "#B89030") ?? .orange,
                hairStyle: .longWavy,
                skinColor:  Color(hex: "#F2C4A0") ?? .orange,
                cheekColor: Color(hex: "#E07070") ?? .red,
                clothingColor: Color(hex: "#6A1030") ?? .red,
                eyeColor:   Color(hex: "#3A2050") ?? .purple,
                lipColor:   Color(hex: "#C03050") ?? .red,
                shoulderWidthRatio: 0.72
            )

        // ── ARIA — confident, athletic, sage/forest palette ──────────────
        case "aria":
            return PortraitConfig(
                bgColors:  [Color(hex: "#071A10") ?? .black,
                            Color(hex: "#1A4A28") ?? .green,
                            Color(hex: "#4A9068") ?? .green],
                hairColor:  Color(hex: "#3A1808") ?? .brown,
                hairColor2: Color(hex: "#5A2810") ?? .brown,
                hairStyle: .mediumStraight,
                skinColor:  Color(hex: "#E0B888") ?? .orange,
                cheekColor: Color(hex: "#C07050") ?? .orange,
                clothingColor: Color(hex: "#1A3020") ?? .green,
                eyeColor:   Color(hex: "#1A2810") ?? .black,
                lipColor:   Color(hex: "#A85838") ?? .brown,
                shoulderWidthRatio: 0.78
            )

        // ── KEL — soft, grounding, mint/earth palette ────────────────────
        case "kel":
            return PortraitConfig(
                bgColors:  [Color(hex: "#071510") ?? .black,
                            Color(hex: "#183C28") ?? .green,
                            Color(hex: "#50886A") ?? .green],
                hairColor:  Color(hex: "#4A2818") ?? .brown,
                hairColor2: Color(hex: "#704030") ?? .brown,
                hairStyle: .longStraight,
                skinColor:  Color(hex: "#D8A878") ?? .orange,
                cheekColor: Color(hex: "#B86848") ?? .brown,
                clothingColor: Color(hex: "#203828") ?? .green,
                eyeColor:   Color(hex: "#182010") ?? .black,
                lipColor:   Color(hex: "#905848") ?? .brown,
                shoulderWidthRatio: 0.70
            )

        // ── MARCO — strong, dark, slate-blue/navy palette ────────────────
        case "marco":
            return PortraitConfig(
                bgColors:  [Color(hex: "#060810") ?? .black,
                            Color(hex: "#101828") ?? .blue,
                            Color(hex: "#283858") ?? .blue],
                hairColor:  Color(hex: "#100C08") ?? .black,
                hairColor2: nil,
                hairStyle: .longStraight,
                skinColor:  Color(hex: "#B88060") ?? .brown,
                cheekColor: Color(hex: "#906040") ?? .brown,
                clothingColor: Color(hex: "#080C14") ?? .black,
                eyeColor:   Color(hex: "#0A0C10") ?? .black,
                lipColor:   Color(hex: "#785040") ?? .brown,
                shoulderWidthRatio: 0.90
            )

        // ── DANTE — romantic, poetic, warm amber/mahogany palette ────────
        case "dante":
            return PortraitConfig(
                bgColors:  [Color(hex: "#120600") ?? .black,
                            Color(hex: "#4A1C08") ?? .brown,
                            Color(hex: "#904028") ?? .orange],
                hairColor:  Color(hex: "#0C0604") ?? .black,
                hairColor2: Color(hex: "#1C1008") ?? .brown,
                hairStyle: .mediumCurly,
                skinColor:  Color(hex: "#C08860") ?? .brown,
                cheekColor: Color(hex: "#A06040") ?? .brown,
                clothingColor: Color(hex: "#180A04") ?? .black,
                eyeColor:   Color(hex: "#0C0804") ?? .black,
                lipColor:   Color(hex: "#804030") ?? .brown,
                shoulderWidthRatio: 0.86
            )

        // ── KAI — steady, clean, ocean-blue palette ──────────────────────
        case "kai":
            return PortraitConfig(
                bgColors:  [Color(hex: "#030C12") ?? .black,
                            Color(hex: "#082030") ?? .blue,
                            Color(hex: "#205070") ?? .blue],
                hairColor:  Color(hex: "#0A0808") ?? .black,
                hairColor2: nil,
                hairStyle: .shortClean,
                skinColor:  Color(hex: "#A87858") ?? .brown,
                cheekColor: Color(hex: "#886040") ?? .brown,
                clothingColor: Color(hex: "#060C10") ?? .black,
                eyeColor:   Color(hex: "#080A0C") ?? .black,
                lipColor:   Color(hex: "#705040") ?? .brown,
                shoulderWidthRatio: 0.88
            )

        default:
            return PortraitConfig(
                bgColors: [.gray.opacity(0.8), .black],
                hairColor: .gray, hairColor2: nil, hairStyle: .shortClean,
                skinColor: Color(hex: "#D4A882") ?? .orange,
                cheekColor: .pink.opacity(0.3),
                clothingColor: .black,
                eyeColor: .black,
                lipColor: .pink,
                shoulderWidthRatio: 0.75
            )
        }
    }
}
