import SwiftUI

// MARK: - PortraitStyle
//
// Per-companion colour palette for the illustrated portrait.
// Six companions: Luna, Aria, Kel (female) · Marco, Dante, Kai (male)

struct PortraitStyle {
    let bgTop:          Color
    let bgBottom:       Color
    let skinColor:      Color
    let skinLight:      Color
    let hairColor:      Color
    let hairHighlight:  Color
    let browColor:      Color
    let irisColor:      Color
    let lipColor:       Color
    let clothingColor:  Color
    let stubbleColor:   Color   // male only; .clear for female

    static func style(for id: String) -> PortraitStyle {
        switch id {

        // ── FEMALE ────────────────────────────────────────────────────
        case "luna":      // warm golden blonde, red top, green eyes
            return PortraitStyle(
                bgTop:         Color(hex: "#3D1A2C"),
                bgBottom:      Color(hex: "#1A0E1E"),
                skinColor:     Color(hex: "#F2B890"),
                skinLight:     Color(hex: "#FACCAA"),
                hairColor:     Color(hex: "#D4943A"),
                hairHighlight: Color(hex: "#F0C878").opacity(0.55),
                browColor:     Color(hex: "#8B4A18"),
                irisColor:     Color(hex: "#5C8A3C"),
                lipColor:      Color(hex: "#E84060"),
                clothingColor: Color(hex: "#C01828"),
                stubbleColor:  .clear
            )
        case "aria":      // dark hair, teal top, blue eyes
            return PortraitStyle(
                bgTop:         Color(hex: "#1A2C2A"),
                bgBottom:      Color(hex: "#0E1E1A"),
                skinColor:     Color(hex: "#D4906A"),
                skinLight:     Color(hex: "#E8A882"),
                hairColor:     Color(hex: "#2C1808"),
                hairHighlight: Color(hex: "#6B3820").opacity(0.50),
                browColor:     Color(hex: "#1A0E06"),
                irisColor:     Color(hex: "#3C5C8A"),
                lipColor:      Color(hex: "#CC4460"),
                clothingColor: Color(hex: "#1A6B8A"),
                stubbleColor:  .clear
            )
        case "kel":       // auburn hair, sage top, hazel eyes
            return PortraitStyle(
                bgTop:         Color(hex: "#1C2A1A"),
                bgBottom:      Color(hex: "#101E10"),
                skinColor:     Color(hex: "#E8AE8A"),
                skinLight:     Color(hex: "#F8C8A8"),
                hairColor:     Color(hex: "#8B3820"),
                hairHighlight: Color(hex: "#C05830").opacity(0.50),
                browColor:     Color(hex: "#5C2010"),
                irisColor:     Color(hex: "#7A6A30"),
                lipColor:      Color(hex: "#D06050"),
                clothingColor: Color(hex: "#2A6A40"),
                stubbleColor:  .clear
            )

        // ── MALE ──────────────────────────────────────────────────────
        case "marco":     // dark skin, black tee, dark brown eyes, tattoos
            return PortraitStyle(
                bgTop:         Color(hex: "#1A1C2C"),
                bgBottom:      Color(hex: "#0E1018"),
                skinColor:     Color(hex: "#C0854A"),
                skinLight:     Color(hex: "#D8A060"),
                hairColor:     Color(hex: "#0E0A06"),
                hairHighlight: Color(hex: "#2A1808").opacity(0.55),
                browColor:     Color(hex: "#0A0806"),
                irisColor:     Color(hex: "#4A3010"),
                lipColor:      Color(hex: "#A84030"),
                clothingColor: Color(hex: "#181818"),
                stubbleColor:  Color(hex: "#0A0806").opacity(0.20)
            )
        case "dante":     // dark flowing hair, burgundy shirt, warm eyes
            return PortraitStyle(
                bgTop:         Color(hex: "#2C1A10"),
                bgBottom:      Color(hex: "#1E100A"),
                skinColor:     Color(hex: "#C89060"),
                skinLight:     Color(hex: "#E0AA78"),
                hairColor:     Color(hex: "#1A0C04"),
                hairHighlight: Color(hex: "#3C1C0C").opacity(0.55),
                browColor:     Color(hex: "#100804"),
                irisColor:     Color(hex: "#5A3818"),
                lipColor:      Color(hex: "#B85040"),
                clothingColor: Color(hex: "#6B2010"),
                stubbleColor:  Color(hex: "#0A0806").opacity(0.22)
            )
        default:          // kai / unknown — medium skin, navy, blue eyes
            return PortraitStyle(
                bgTop:         Color(hex: "#1A2030"),
                bgBottom:      Color(hex: "#101420"),
                skinColor:     Color(hex: "#DFA878"),
                skinLight:     Color(hex: "#F0BF90"),
                hairColor:     Color(hex: "#1C1008"),
                hairHighlight: Color(hex: "#4A2810").opacity(0.50),
                browColor:     Color(hex: "#180E06"),
                irisColor:     Color(hex: "#2A5080"),
                lipColor:      Color(hex: "#AA4838"),
                clothingColor: Color(hex: "#2A3A5A"),
                stubbleColor:  Color(hex: "#0A0806").opacity(0.16)
            )
        }
    }
}

// MARK: - CompanionPortraitView
//
// Renders a gender-appropriate illustrated portrait for each companion.
// Shows a real asset-catalog photo when present; otherwise draws fully
// in SwiftUI Canvas — no image assets required.

struct CompanionPortraitView: View {
    let companion: CompanionPersonality
    let size: AvatarSize

    private var dimension: CGFloat {
        switch size {
        case .chat:   return 44
        case .card:   return 120
        case .detail: return 200
        }
    }

    var body: some View {
        Group {
            if UIImage(named: companion.avatarImageName) != nil {
                Image(companion.avatarImageName)
                    .resizable()
                    .scaledToFill()
            } else {
                IllustratedPortraitView(
                    gender:      companion.gender,
                    companionId: companion.id,
                    accentColor: companion.accentColor,
                    size:        dimension
                )
            }
        }
        .frame(width: dimension, height: dimension)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(
                companion.accentColor.opacity(0.45),
                lineWidth: max(1.5, dimension * 0.018)
            )
        )
    }
}

// MARK: - IllustratedPortraitView

struct IllustratedPortraitView: View {
    let gender:      CompanionGender
    let companionId: String
    let accentColor: Color
    let size:        CGFloat

    private var style: PortraitStyle { PortraitStyle.style(for: companionId) }

    private let bokeh: [(CGFloat, CGFloat, CGFloat)] = [
        (0.44,  0.28, -0.28), (0.28, -0.22,  0.18),
        (0.32,  0.16,  0.30), (0.22, -0.32, -0.08),
        (0.38,  0.06, -0.18)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [style.bgTop, style.bgBottom],
                startPoint: .top, endPoint: .bottom
            )
            ForEach(0..<bokeh.count, id: \.self) { i in
                let b = bokeh[i]
                Circle()
                    .fill(accentColor.opacity(0.13 + Double(i) * 0.034))
                    .frame(width: size * b.0, height: size * b.0)
                    .offset(x: size * b.1, y: size * b.2)
                    .blur(radius: size * 0.09)
            }
            Canvas { ctx, cs in
                if gender == .female { drawFemale(ctx: ctx, s: cs) }
                else                 { drawMale(ctx: ctx, s: cs)   }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: Female portrait
    // ─────────────────────────────────────────────────────────────────

    private func drawFemale(ctx: GraphicsContext, s: CGSize) {
        let w = s.width, h = s.height

        // 1. Hair — large back sweep
        var hairBack = Path()
        hairBack.move(to: CGPoint(x: w * 0.12, y: h * 0.30))
        hairBack.addCurve(to: CGPoint(x: w * 0.88, y: h * 0.30),
                          control1: CGPoint(x: w * 0.10, y: -h * 0.06),
                          control2: CGPoint(x: w * 0.90, y: -h * 0.06))
        hairBack.addCurve(to: CGPoint(x: w * 0.86, y: h * 0.94),
                          control1: CGPoint(x: w * 1.06, y: h * 0.52),
                          control2: CGPoint(x: w * 1.02, y: h * 0.78))
        hairBack.addLine(to: CGPoint(x: w * 0.14, y: h * 0.94))
        hairBack.addCurve(to: CGPoint(x: w * 0.12, y: h * 0.30),
                          control1: CGPoint(x: -w * 0.02, y: h * 0.78),
                          control2: CGPoint(x: -w * 0.06, y: h * 0.52))
        hairBack.closeSubpath()
        ctx.fill(hairBack, with: .color(style.hairColor))

        // 2. Shoulders / clothing
        var shoulders = Path()
        shoulders.move(to: CGPoint(x: 0, y: h))
        shoulders.addLine(to: CGPoint(x: w, y: h))
        shoulders.addLine(to: CGPoint(x: w, y: h * 0.76))
        shoulders.addCurve(to: CGPoint(x: 0, y: h * 0.76),
                           control1: CGPoint(x: w * 0.78, y: h * 0.64),
                           control2: CGPoint(x: w * 0.22, y: h * 0.64))
        shoulders.closeSubpath()
        ctx.fill(shoulders, with: .color(style.clothingColor))

        // 3. Neck
        let nW = w * 0.18
        ctx.fill(Path(roundedRect: CGRect(x: (w - nW) / 2, y: h * 0.61,
                                           width: nW, height: h * 0.22),
                      cornerRadius: nW * 0.45),
                 with: .color(style.skinColor))

        // 4. Face oval
        let fW = w * 0.60, fH = h * 0.52
        let fX = (w - fW) / 2, fY = h * 0.13
        ctx.fill(Path(ellipseIn: CGRect(x: fX, y: fY, width: fW, height: fH)),
                 with: .linearGradient(
                    Gradient(colors: [style.skinLight, style.skinColor]),
                    startPoint: CGPoint(x: w / 2, y: fY),
                    endPoint:   CGPoint(x: w / 2, y: fY + fH)))

        // 5. Hair — front side strands framing the face
        for sign: CGFloat in [-1, 1] {
            let flip: CGFloat = sign < 0 ? 1 : -1
            let sX: CGFloat   = sign < 0 ? w * 0.13 : w * 0.87
            var strand = Path()
            strand.move(to: CGPoint(x: sX, y: h * 0.08))
            strand.addCurve(to:       CGPoint(x: sX + sign * (-w * 0.10), y: h * 0.56),
                            control1: CGPoint(x: sX + flip * w * 0.03,    y: h * 0.26),
                            control2: CGPoint(x: sX + sign * (-w * 0.06), y: h * 0.42))
            strand.addLine(to: CGPoint(x: sX + sign * (-w * 0.04), y: h * 0.56))
            strand.addCurve(to:       CGPoint(x: sX + sign * w * 0.06, y: h * 0.08),
                            control1: CGPoint(x: sX + sign * (-w * 0.01), y: h * 0.40),
                            control2: CGPoint(x: sX + sign * w * 0.04,    y: h * 0.24))
            strand.closeSubpath()
            ctx.fill(strand, with: .color(style.hairColor))
        }

        // 6. Eyebrows — arched, feminine
        for sign: CGFloat in [-1, 1] {
            let cx = w * 0.5 + sign * w * 0.154
            var brow = Path()
            brow.move(to: CGPoint(x: cx - w * 0.082, y: h * 0.322))
            brow.addCurve(to:       CGPoint(x: cx + w * 0.082, y: h * 0.322),
                          control1: CGPoint(x: cx - w * 0.034, y: h * 0.296),
                          control2: CGPoint(x: cx + w * 0.034, y: h * 0.304))
            ctx.stroke(brow, with: .color(style.browColor),
                       style: StrokeStyle(lineWidth: w * 0.022, lineCap: .round))
        }

        // 7. Eyes — large, expressive, with lashes
        let eY = h * 0.352, eW = w * 0.142, eH = eW * 0.64
        for sign: CGFloat in [-1, 1] {
            let eX = w * 0.5 + sign * w * 0.154 - eW / 2
            let ic = CGPoint(x: eX + eW / 2, y: eY + eH * 0.50)
            let iR = eH * 0.46, pR = iR * 0.56, cR = pR * 0.40
            ctx.fill(Path(ellipseIn: CGRect(x: eX, y: eY, width: eW, height: eH)),
                     with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: ic.x - iR, y: ic.y - iR,
                                             width: iR * 2, height: iR * 2)),
                     with: .color(style.irisColor))
            ctx.fill(Path(ellipseIn: CGRect(x: ic.x - pR, y: ic.y - pR,
                                             width: pR * 2, height: pR * 2)),
                     with: .color(Color(hex: "#080808")))
            ctx.fill(Path(ellipseIn: CGRect(x: ic.x + pR * 0.14, y: ic.y - pR * 0.56,
                                             width: cR * 2, height: cR * 2)),
                     with: .color(.white.opacity(0.88)))
            var lash = Path()
            lash.move(to: CGPoint(x: eX - w * 0.005, y: eY + eH * 0.16))
            lash.addQuadCurve(to:      CGPoint(x: eX + eW + w * 0.005, y: eY + eH * 0.16),
                              control: CGPoint(x: eX + eW / 2, y: eY - eH * 0.20))
            ctx.stroke(lash, with: .color(Color(hex: "#100808")),
                       style: StrokeStyle(lineWidth: w * 0.027, lineCap: .round))
        }

        // 8. Nose — subtle nostril dots
        let noseY = h * 0.468
        for dx: CGFloat in [-0.026, 0.010] {
            ctx.fill(Path(ellipseIn: CGRect(x: w / 2 + dx * w, y: noseY,
                                             width: w * 0.018, height: w * 0.011)),
                     with: .color(style.skinColor.opacity(0.65)))
        }

        // 9. Lips — Cupid's bow
        let lY = h * 0.516, lW = w * 0.232, lH = lW * 0.40
        var lips = Path()
        lips.move(to: CGPoint(x: w / 2 - lW / 2, y: lY + lH * 0.34))
        lips.addCurve(to:       CGPoint(x: w / 2 - lW * 0.11, y: lY),
                      control1: CGPoint(x: w / 2 - lW * 0.34, y: lY + lH * 0.10),
                      control2: CGPoint(x: w / 2 - lW * 0.20, y: lY))
        lips.addCurve(to:       CGPoint(x: w / 2 + lW * 0.11, y: lY),
                      control1: CGPoint(x: w / 2 - lW * 0.02, y: lY + lH * 0.20),
                      control2: CGPoint(x: w / 2 + lW * 0.02, y: lY + lH * 0.20))
        lips.addCurve(to:       CGPoint(x: w / 2 + lW / 2, y: lY + lH * 0.34),
                      control1: CGPoint(x: w / 2 + lW * 0.20, y: lY),
                      control2: CGPoint(x: w / 2 + lW * 0.34, y: lY + lH * 0.10))
        lips.addCurve(to:       CGPoint(x: w / 2 - lW / 2, y: lY + lH * 0.34),
                      control1: CGPoint(x: w / 2 + lW * 0.30, y: lY + lH * 0.86),
                      control2: CGPoint(x: w / 2 - lW * 0.30, y: lY + lH * 0.86))
        ctx.fill(lips, with: .color(style.lipColor))
        ctx.fill(Path(ellipseIn: CGRect(x: w / 2 - lW * 0.11, y: lY + lH * 0.08,
                                         width: lW * 0.22, height: lH * 0.22)),
                 with: .color(.white.opacity(0.26)))

        // 10. Blush — soft rosy cheeks
        let bR = w * 0.094, bY = h * 0.454
        for bX: CGFloat in [w * 0.162, w * 0.690] {
            ctx.fill(Path(ellipseIn: CGRect(x: bX, y: bY,
                                             width: bR * 2, height: bR * 0.54)),
                     with: .color(Color(hex: "#F08090").opacity(0.22)))
        }

        // 11. Hair highlight strand
        var hl = Path()
        hl.move(to: CGPoint(x: w * 0.33, y: h * 0.02))
        hl.addCurve(to:       CGPoint(x: w * 0.46, y: h * 0.22),
                    control1: CGPoint(x: w * 0.35, y: h * 0.08),
                    control2: CGPoint(x: w * 0.43, y: h * 0.14))
        hl.addLine(to: CGPoint(x: w * 0.49, y: h * 0.22))
        hl.addCurve(to:       CGPoint(x: w * 0.36, y: h * 0.02),
                    control1: CGPoint(x: w * 0.46, y: h * 0.13),
                    control2: CGPoint(x: w * 0.38, y: h * 0.07))
        hl.closeSubpath()
        ctx.fill(hl, with: .color(style.hairHighlight))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: Male portrait
    // ─────────────────────────────────────────────────────────────────

    private func drawMale(ctx: GraphicsContext, s: CGSize) {
        let w = s.width, h = s.height

        // 1. Shoulders / clothing — wide, athletic
        var body = Path()
        body.move(to: CGPoint(x: 0, y: h))
        body.addLine(to: CGPoint(x: w, y: h))
        body.addLine(to: CGPoint(x: w, y: h * 0.70))
        body.addCurve(to: CGPoint(x: 0, y: h * 0.70),
                      control1: CGPoint(x: w * 0.82, y: h * 0.56),
                      control2: CGPoint(x: w * 0.18, y: h * 0.56))
        body.closeSubpath()
        ctx.fill(body, with: .color(style.clothingColor))

        // 2. Hair — short, structured
        var hair = Path()
        hair.move(to: CGPoint(x: w * 0.16, y: h * 0.31))
        hair.addCurve(to:       CGPoint(x: w * 0.84, y: h * 0.31),
                      control1: CGPoint(x: w * 0.14, y: -h * 0.02),
                      control2: CGPoint(x: w * 0.86, y: -h * 0.02))
        hair.addCurve(to:       CGPoint(x: w * 0.79, y: h * 0.22),
                      control1: CGPoint(x: w * 0.88, y: h * 0.24),
                      control2: CGPoint(x: w * 0.83, y: h * 0.20))
        hair.addCurve(to:       CGPoint(x: w * 0.21, y: h * 0.22),
                      control1: CGPoint(x: w * 0.62, y: h * 0.06),
                      control2: CGPoint(x: w * 0.38, y: h * 0.06))
        hair.addCurve(to:       CGPoint(x: w * 0.16, y: h * 0.31),
                      control1: CGPoint(x: w * 0.17, y: h * 0.20),
                      control2: CGPoint(x: w * 0.14, y: h * 0.24))
        hair.closeSubpath()
        ctx.fill(hair, with: .color(style.hairColor))

        var hhl = Path()
        hhl.move(to: CGPoint(x: w * 0.34, y: h * 0.10))
        hhl.addCurve(to:       CGPoint(x: w * 0.54, y: h * 0.14),
                     control1: CGPoint(x: w * 0.40, y: h * 0.08),
                     control2: CGPoint(x: w * 0.50, y: h * 0.10))
        hhl.addLine(to: CGPoint(x: w * 0.54, y: h * 0.18))
        hhl.addCurve(to:       CGPoint(x: w * 0.34, y: h * 0.14),
                     control1: CGPoint(x: w * 0.50, y: h * 0.16),
                     control2: CGPoint(x: w * 0.40, y: h * 0.16))
        hhl.closeSubpath()
        ctx.fill(hhl, with: .color(style.hairHighlight))

        // 3. Neck — wider
        let nW = w * 0.24
        ctx.fill(Path(roundedRect: CGRect(x: (w - nW) / 2, y: h * 0.59,
                                           width: nW, height: h * 0.20),
                      cornerRadius: nW * 0.30),
                 with: .color(style.skinColor))

        // 4. Face — angular jaw
        let ftY = h * 0.17, fbY = h * 0.64
        let ftW = w * 0.54, fmW = w * 0.60, fbW = w * 0.46
        var face = Path()
        face.move(to: CGPoint(x: w / 2 - ftW / 2, y: ftY))
        face.addCurve(to:       CGPoint(x: w / 2 + ftW / 2, y: ftY),
                      control1: CGPoint(x: w / 2 - ftW / 2 + w * 0.02, y: ftY - h * 0.02),
                      control2: CGPoint(x: w / 2 + ftW / 2 - w * 0.02, y: ftY - h * 0.02))
        face.addCurve(to:       CGPoint(x: w / 2 + fbW / 2, y: fbY - h * 0.06),
                      control1: CGPoint(x: w / 2 + fmW / 2, y: ftY + h * 0.18),
                      control2: CGPoint(x: w / 2 + fmW / 2, y: ftY + h * 0.30))
        face.addCurve(to:       CGPoint(x: w / 2, y: fbY),
                      control1: CGPoint(x: w / 2 + fbW / 2, y: fbY - h * 0.01),
                      control2: CGPoint(x: w / 2 + fbW * 0.24, y: fbY + h * 0.01))
        face.addCurve(to:       CGPoint(x: w / 2 - fbW / 2, y: fbY - h * 0.06),
                      control1: CGPoint(x: w / 2 - fbW * 0.24, y: fbY + h * 0.01),
                      control2: CGPoint(x: w / 2 - fbW / 2, y: fbY - h * 0.01))
        face.addCurve(to:       CGPoint(x: w / 2 - ftW / 2, y: ftY),
                      control1: CGPoint(x: w / 2 - fmW / 2, y: ftY + h * 0.30),
                      control2: CGPoint(x: w / 2 - fmW / 2, y: ftY + h * 0.18))
        face.closeSubpath()
        ctx.fill(face, with: .linearGradient(
            Gradient(colors: [style.skinLight, style.skinColor]),
            startPoint: CGPoint(x: w / 2, y: ftY),
            endPoint:   CGPoint(x: w / 2, y: fbY)))

        // 5. Jaw stubble shadow
        if style.stubbleColor != .clear {
            var jaw = Path()
            jaw.move(to: CGPoint(x: w / 2 - fbW * 0.42, y: h * 0.51))
            jaw.addQuadCurve(to:      CGPoint(x: w / 2 + fbW * 0.42, y: h * 0.51),
                              control: CGPoint(x: w / 2, y: fbY + h * 0.05))
            jaw.addCurve(to:       CGPoint(x: w / 2 - fbW * 0.42, y: h * 0.51),
                         control1: CGPoint(x: w / 2 + fbW * 0.18, y: h * 0.56),
                         control2: CGPoint(x: w / 2 - fbW * 0.18, y: h * 0.56))
            ctx.fill(jaw, with: .color(style.stubbleColor))
        }

        // 6. Eyebrows — heavy, strong
        for sign: CGFloat in [-1, 1] {
            let cx = w * 0.5 + sign * w * 0.156
            var brow = Path()
            brow.move(to: CGPoint(x: cx - w * 0.090, y: h * 0.307))
            brow.addCurve(to:       CGPoint(x: cx + w * 0.090, y: h * 0.307),
                          control1: CGPoint(x: cx - w * 0.038, y: h * 0.286),
                          control2: CGPoint(x: cx + w * 0.038, y: h * 0.294))
            ctx.stroke(brow, with: .color(style.browColor),
                       style: StrokeStyle(lineWidth: w * 0.030, lineCap: .round))
        }

        // 7. Eyes — hooded, intense
        let eY = h * 0.348, eW = w * 0.132, eH = eW * 0.55
        for sign: CGFloat in [-1, 1] {
            let eX = w * 0.5 + sign * w * 0.156 - eW / 2
            let ic = CGPoint(x: eX + eW / 2, y: eY + eH * 0.50)
            let iR = eH * 0.46, pR = iR * 0.56, cR = pR * 0.38
            ctx.fill(Path(ellipseIn: CGRect(x: eX, y: eY, width: eW, height: eH)),
                     with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: ic.x - iR, y: ic.y - iR,
                                             width: iR * 2, height: iR * 2)),
                     with: .color(style.irisColor))
            ctx.fill(Path(ellipseIn: CGRect(x: ic.x - pR, y: ic.y - pR,
                                             width: pR * 2, height: pR * 2)),
                     with: .color(Color(hex: "#080808")))
            ctx.fill(Path(ellipseIn: CGRect(x: ic.x + pR * 0.12, y: ic.y - pR * 0.52,
                                             width: cR * 2, height: cR * 2)),
                     with: .color(.white.opacity(0.82)))
            var lash = Path()
            lash.move(to: CGPoint(x: eX, y: eY + eH * 0.18))
            lash.addQuadCurve(to:      CGPoint(x: eX + eW, y: eY + eH * 0.18),
                              control: CGPoint(x: eX + eW / 2, y: eY - eH * 0.14))
            ctx.stroke(lash, with: .color(Color(hex: "#080808")),
                       style: StrokeStyle(lineWidth: w * 0.022, lineCap: .round))
        }

        // 8. Nose — stronger bridge
        let noseTopY = h * 0.394, noseBotY = h * 0.456
        var nBridge = Path()
        nBridge.move(to: CGPoint(x: w / 2 - w * 0.010, y: noseTopY))
        nBridge.addCurve(to:       CGPoint(x: w / 2 - w * 0.030, y: noseBotY),
                         control1: CGPoint(x: w / 2 - w * 0.016, y: noseTopY + h * 0.03),
                         control2: CGPoint(x: w / 2 - w * 0.032, y: noseBotY - h * 0.02))
        nBridge.move(to: CGPoint(x: w / 2 + w * 0.010, y: noseTopY))
        nBridge.addCurve(to:       CGPoint(x: w / 2 + w * 0.030, y: noseBotY),
                         control1: CGPoint(x: w / 2 + w * 0.016, y: noseTopY + h * 0.03),
                         control2: CGPoint(x: w / 2 + w * 0.032, y: noseBotY - h * 0.02))
        ctx.stroke(nBridge, with: .color(style.skinColor.opacity(0.60)),
                   style: StrokeStyle(lineWidth: w * 0.016, lineCap: .round))
        for dx: CGFloat in [-0.040, 0.022] {
            ctx.fill(Path(ellipseIn: CGRect(x: w / 2 + dx * w, y: noseBotY,
                                             width: w * 0.022, height: w * 0.014)),
                     with: .color(style.skinColor.opacity(0.62)))
        }

        // 9. Lips — defined, thinner
        let lY = h * 0.494, lW = w * 0.198, lH = lW * 0.33
        var lips = Path()
        lips.move(to: CGPoint(x: w / 2 - lW / 2, y: lY + lH * 0.30))
        lips.addCurve(to:       CGPoint(x: w / 2 + lW / 2, y: lY + lH * 0.30),
                      control1: CGPoint(x: w / 2 - lW * 0.18, y: lY - lH * 0.06),
                      control2: CGPoint(x: w / 2 + lW * 0.18, y: lY - lH * 0.06))
        lips.addCurve(to:       CGPoint(x: w / 2 - lW / 2, y: lY + lH * 0.30),
                      control1: CGPoint(x: w / 2 + lW * 0.28, y: lY + lH * 0.82),
                      control2: CGPoint(x: w / 2 - lW * 0.28, y: lY + lH * 0.82))
        ctx.fill(lips, with: .color(style.lipColor))

        // 10. Tattoo hint — faint dot cluster on right shoulder
        if style.stubbleColor != .clear {
            let tX = w * 0.74, tY = h * 0.80
            let dots: [(CGFloat, CGFloat)] = [
                (0, 0), (w * 0.04, h * 0.02), (w * 0.08, 0),
                (w * 0.02, h * 0.035), (w * 0.06, h * 0.035), (w * 0.04, h * 0.06)
            ]
            for d in dots {
                ctx.fill(Path(ellipseIn: CGRect(x: tX + d.0, y: tY + d.1,
                                                 width: w * 0.014, height: w * 0.010)),
                         with: .color(.black.opacity(0.18)))
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Female companions") {
    HStack(spacing: 16) {
        ForEach(["luna", "aria", "kel"], id: \.self) { id in
            let c = CompanionPersonality.all.first(where: { $0.id == id })!
            VStack(spacing: 6) {
                CompanionPortraitView(companion: c, size: .detail)
                Text(c.name).font(.caption).foregroundColor(.white)
            }
        }
    }
    .padding(24)
    .background(Color(hex: "#0D1117"))
}

#Preview("Male companions") {
    HStack(spacing: 16) {
        ForEach(["marco", "dante", "kai"], id: \.self) { id in
            let c = CompanionPersonality.all.first(where: { $0.id == id })!
            VStack(spacing: 6) {
                CompanionPortraitView(companion: c, size: .detail)
                Text(c.name).font(.caption).foregroundColor(.white)
            }
        }
    }
    .padding(24)
    .background(Color(hex: "#0D1117"))
}

#Preview("Chat size — all") {
    let luna = CompanionPersonality.luna
    HStack(spacing: 8) {
        CompanionPortraitView(companion: luna, size: .chat)
        CompanionPortraitView(companion: luna, size: .card)
        CompanionPortraitView(companion: luna, size: .detail)
    }
    .padding()
    .background(Color(hex: "#161B22"))
}
#endif
