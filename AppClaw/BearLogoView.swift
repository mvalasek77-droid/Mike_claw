import SwiftUI

// MARK: - BearLogoView
//
// Cute, refined geometric bear head — entirely SwiftUI, no assets.
// Scales from 24 pt (nav bar) to 512 pt (splash).
//
// Design language: soft rounded proportions, big expressive eyes,
// rose blush, gentle smile — think quality plush toy, not cartoon.

struct BearLogoView: View {
    var size: CGFloat = 64
    var showBackground: Bool = true

    // Derived scale helpers
    private var s: CGFloat { size }

    var body: some View {
        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: s * 0.22)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#1C2438") ?? .black,
                                 Color(hex: "#0D1117") ?? .black],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .shadow(color: (Color(hex: "#FF9F0A") ?? .orange).opacity(0.28),
                            radius: s * 0.14, y: s * 0.05)
            }

            Canvas { ctx, cs in
                drawBear(ctx: ctx, size: cs)
            }
            .frame(width: s * 0.88, height: s * 0.88)
        }
        .frame(width: s, height: s)
    }

    // MARK: - Bear drawing

    private func drawBear(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height

        // ── Ear positions ─────────────────────────────────────────────
        let earR  = w * 0.195
        let earLX = w * 0.13,  earRX = w * 0.675
        let earY  = h * 0.045

        // ── Face center ───────────────────────────────────────────────
        let faceR = w * 0.415
        let faceX = w * 0.5 - faceR
        let faceY = h * 0.17

        let furGrad = Gradient(colors: [
            Color(hex: "#E8A84A") ?? .orange,
            Color(hex: "#D4862A") ?? .brown,
            Color(hex: "#C07020") ?? .brown
        ])
        let furFill = GraphicsContext.Shading.linearGradient(
            furGrad,
            startPoint: CGPoint(x: w * 0.2, y: 0),
            endPoint:   CGPoint(x: w * 0.8, y: h)
        )

        // 1. Outer ears (fur)
        ctx.fill(Path(ellipseIn: CGRect(x: earLX, y: earY, width: earR*2, height: earR*2)), with: furFill)
        ctx.fill(Path(ellipseIn: CGRect(x: earRX, y: earY, width: earR*2, height: earR*2)), with: furFill)

        // 2. Inner ears (soft rose-pink)
        let iEarR = earR * 0.58
        let iEarFill = GraphicsContext.Shading.color(Color(hex: "#F0A0A8") ?? .pink)
        ctx.fill(Path(ellipseIn: CGRect(
            x: earLX + (earR - iEarR), y: earY + (earR - iEarR) + earR * 0.08,
            width: iEarR*2, height: iEarR*2)), with: iEarFill)
        ctx.fill(Path(ellipseIn: CGRect(
            x: earRX + (earR - iEarR), y: earY + (earR - iEarR) + earR * 0.08,
            width: iEarR*2, height: iEarR*2)), with: iEarFill)

        // 3. Face circle
        ctx.fill(Path(ellipseIn: CGRect(x: faceX, y: faceY, width: faceR*2, height: faceR*2)), with: furFill)

        // 4. Snout — creamy oval
        let snoutW = faceR * 0.72, snoutH = faceR * 0.44
        let snoutX = w/2 - snoutW/2, snoutY = h * 0.575
        ctx.fill(Path(ellipseIn: CGRect(x: snoutX, y: snoutY, width: snoutW, height: snoutH)),
                 with: .color(Color(hex: "#F5DFA8") ?? .yellow))

        // 5. Blush circles (rose, semi-transparent)
        let blushR = faceR * 0.28
        let blushY = h * 0.545
        let blushFill = GraphicsContext.Shading.color((Color(hex: "#F07080") ?? .red).opacity(0.30))
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.155, y: blushY, width: blushR*2, height: blushR*0.7)), with: blushFill)
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.645, y: blushY, width: blushR*2, height: blushR*0.7)), with: blushFill)

        // 6. Eyes
        let eyeW  = faceR * 0.30, eyeH = eyeW * 1.12
        let eyeY  = h * 0.385
        let eyeLX = w * 0.285 - eyeW/2
        let eyeRX = w * 0.715 - eyeW/2

        // Whites
        ctx.fill(Path(ellipseIn: CGRect(x: eyeLX - eyeW*0.04, y: eyeY - eyeH*0.04,
                                         width: eyeW*1.08, height: eyeH*1.08)), with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: eyeRX - eyeW*0.04, y: eyeY - eyeH*0.04,
                                         width: eyeW*1.08, height: eyeH*1.08)), with: .color(.white))

        // Irises — warm brown
        let irisGrad = Gradient(colors: [Color(hex: "#5C3010") ?? .brown, Color(hex: "#3A1C08") ?? .brown])
        let irisFill = GraphicsContext.Shading.radialGradient(
            irisGrad, center: CGPoint(x: w*0.285, y: eyeY + eyeH*0.46),
            startRadius: 0, endRadius: eyeW * 0.5)
        let irisGrad2 = Gradient(colors: [Color(hex: "#5C3010") ?? .brown, Color(hex: "#3A1C08") ?? .brown])
        let irisFill2 = GraphicsContext.Shading.radialGradient(
            irisGrad2, center: CGPoint(x: w*0.715, y: eyeY + eyeH*0.46),
            startRadius: 0, endRadius: eyeW * 0.5)
        ctx.fill(Path(ellipseIn: CGRect(x: eyeLX, y: eyeY, width: eyeW, height: eyeH)), with: irisFill)
        ctx.fill(Path(ellipseIn: CGRect(x: eyeRX, y: eyeY, width: eyeW, height: eyeH)), with: irisFill2)

        // Pupils — deep dark
        let pupW = eyeW * 0.55, pupH = eyeH * 0.62
        ctx.fill(Path(ellipseIn: CGRect(x: eyeLX + (eyeW-pupW)/2, y: eyeY + (eyeH-pupH)/2,
                                         width: pupW, height: pupH)),
                 with: .color(Color(hex: "#120808") ?? .black))
        ctx.fill(Path(ellipseIn: CGRect(x: eyeRX + (eyeW-pupW)/2, y: eyeY + (eyeH-pupH)/2,
                                         width: pupW, height: pupH)),
                 with: .color(Color(hex: "#120808") ?? .black))

        // Sparkle highlights
        let spkW = eyeW * 0.28
        ctx.fill(Path(ellipseIn: CGRect(x: eyeLX + eyeW*0.55, y: eyeY + eyeH*0.10, width: spkW, height: spkW)),
                 with: .color(.white.opacity(0.85)))
        ctx.fill(Path(ellipseIn: CGRect(x: eyeRX + eyeW*0.55, y: eyeY + eyeH*0.10, width: spkW, height: spkW)),
                 with: .color(.white.opacity(0.85)))
        // Tiny second sparkle
        let spk2 = spkW * 0.45
        ctx.fill(Path(ellipseIn: CGRect(x: eyeLX + eyeW*0.25, y: eyeY + eyeH*0.52, width: spk2, height: spk2)),
                 with: .color(.white.opacity(0.50)))
        ctx.fill(Path(ellipseIn: CGRect(x: eyeRX + eyeW*0.25, y: eyeY + eyeH*0.52, width: spk2, height: spk2)),
                 with: .color(.white.opacity(0.50)))

        // 7. Nose — cute wide rounded oval
        let nosW = snoutW * 0.32, nosH = nosW * 0.58
        ctx.fill(Path(ellipseIn: CGRect(x: w/2 - nosW/2, y: snoutY + snoutH*0.14,
                                         width: nosW, height: nosH)),
                 with: .color(Color(hex: "#2A1008") ?? .black))

        // 8. Smile — two short curved strokes from nose base
        var smile = Path()
        // Left curve
        smile.move(to:    CGPoint(x: w/2 - nosW*0.5, y: snoutY + snoutH*0.40))
        smile.addCurve(
            to:       CGPoint(x: w/2 - snoutW*0.28, y: snoutY + snoutH*0.72),
            control1: CGPoint(x: w/2 - nosW*0.6,    y: snoutY + snoutH*0.60),
            control2: CGPoint(x: w/2 - snoutW*0.22, y: snoutY + snoutH*0.60)
        )
        // Right curve
        smile.move(to:    CGPoint(x: w/2 + nosW*0.5, y: snoutY + snoutH*0.40))
        smile.addCurve(
            to:       CGPoint(x: w/2 + snoutW*0.28, y: snoutY + snoutH*0.72),
            control1: CGPoint(x: w/2 + nosW*0.6,    y: snoutY + snoutH*0.60),
            control2: CGPoint(x: w/2 + snoutW*0.22, y: snoutY + snoutH*0.60)
        )
        ctx.stroke(smile,
                   with: .color(Color(hex: "#2A1008") ?? .black),
                   style: StrokeStyle(lineWidth: w * 0.025, lineCap: .round))
    }
}

// MARK: - BearClawAppIcon
//
// App icon: bear paw / claw as the main element, cute bear face centered
// inside the palm pad.  Paw = 1 large palm oval + 4 toe ovals + 4 claw tips.
// Used for Assets.xcassets (render at 1024×1024 and export).

struct BearIconView: View {
    var size: CGFloat = 1024

    private var s: CGFloat { size }

    var body: some View {
        ZStack {
            // Icon background — deep midnight gradient
            RoundedRectangle(cornerRadius: s * 0.2237)
                .fill(LinearGradient(
                    colors: [Color(hex: "#141C2E") ?? .black,
                             Color(hex: "#0A0E18") ?? .black],
                    startPoint: .top, endPoint: .bottom
                ))

            // Subtle radial glow behind paw
            RadialGradient(
                colors: [(Color(hex: "#E8A040") ?? .orange).opacity(0.22), .clear],
                center: .center,
                startRadius: 0, endRadius: s * 0.42
            )
            .clipShape(RoundedRectangle(cornerRadius: s * 0.2237))

            // Paw claw
            Canvas { ctx, cs in
                drawPaw(ctx: ctx, size: cs)
            }
            .frame(width: s * 0.82, height: s * 0.82)

            // Cute bear face centered in the palm
            BearLogoView(size: s * 0.33, showBackground: false)
                .offset(y: s * 0.065)
        }
        .frame(width: s, height: s)
    }

    // MARK: - Paw drawing

    private func drawPaw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height

        let pawGrad = Gradient(stops: [
            .init(color: Color(hex: "#E8A84A") ?? .orange, location: 0.0),
            .init(color: Color(hex: "#C87020") ?? .brown,  location: 0.6),
            .init(color: Color(hex: "#A05818") ?? .brown,  location: 1.0),
        ])
        let pawFill = GraphicsContext.Shading.linearGradient(
            pawGrad,
            startPoint: CGPoint(x: w * 0.3, y: 0),
            endPoint:   CGPoint(x: w * 0.7, y: h)
        )

        let clawGrad = Gradient(colors: [
            Color(hex: "#F0C060") ?? .yellow,
            Color(hex: "#C88020") ?? .orange,
        ])
        let clawFill = GraphicsContext.Shading.linearGradient(
            clawGrad,
            startPoint: CGPoint(x: w*0.4, y: 0),
            endPoint:   CGPoint(x: w*0.6, y: h*0.4)
        )

        // ── Toe parameters ─────────────────────────────────────────────
        // 4 toes arranged in a gentle arc above the palm
        let toeW  = w * 0.155
        let toeH  = toeW * 1.15
        let toeY  = h * 0.095

        // X centres of 4 toes
        let toeXs: [CGFloat] = [w*0.195, w*0.370, w*0.630, w*0.805]
        // Gentle vertical arc: outer toes slightly lower
        let toeYOffsets: [CGFloat] = [h*0.042, 0, 0, h*0.042]

        // ── Claw tips ──────────────────────────────────────────────────
        let clawLen = h * 0.115
        let clawW   = toeW * 0.36

        // Claw angles (outward fan): left, center-left, center-right, right
        let clawAngles: [Double] = [-38, -14, 14, 38]  // degrees from vertical

        for (i, cx) in toeXs.enumerated() {
            let cy = toeY + toeYOffsets[i]
            let angle = clawAngles[i] * .pi / 180
            let tipX = cx + CGFloat(sin(angle)) * clawLen
            let tipY = cy - CGFloat(cos(angle)) * clawLen

            var claw = Path()
            let baseOffX = CGFloat(cos(angle)) * clawW * 0.5
            let baseOffY = CGFloat(sin(angle)) * clawW * 0.5
            claw.move(to: CGPoint(x: cx - baseOffX, y: cy - baseOffY))
            claw.addQuadCurve(
                to: CGPoint(x: tipX, y: tipY),
                control: CGPoint(
                    x: cx + CGFloat(sin(angle)) * clawLen * 0.55 - baseOffX * 0.3,
                    y: cy - CGFloat(cos(angle)) * clawLen * 0.55
                )
            )
            claw.addLine(to: CGPoint(x: cx + baseOffX, y: cy + baseOffY))
            claw.closeSubpath()
            ctx.fill(claw, with: clawFill)
        }

        // ── Toe pads ───────────────────────────────────────────────────
        for (i, cx) in toeXs.enumerated() {
            let cy = toeY + toeYOffsets[i]
            ctx.fill(Path(ellipseIn: CGRect(x: cx - toeW/2, y: cy,
                                             width: toeW, height: toeH)), with: pawFill)
        }

        // ── Palm pad ───────────────────────────────────────────────────
        let palmW = w * 0.72, palmH = h * 0.60
        let palmX = (w - palmW) / 2, palmY = h * 0.35
        ctx.fill(Path(ellipseIn: CGRect(x: palmX, y: palmY, width: palmW, height: palmH)),
                 with: pawFill)

        // Palm inner shadow / depth
        let innerW = palmW * 0.80, innerH = palmH * 0.80
        let innerX = (w - innerW) / 2, innerY = palmY + palmH * 0.12
        ctx.fill(Path(ellipseIn: CGRect(x: innerX, y: innerY, width: innerW, height: innerH)),
                 with: .color((Color(hex: "#E0982A") ?? .orange).opacity(0.35)))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Bear logo sizes") {
    HStack(spacing: 16) {
        ForEach([24, 44, 64, 96, 128], id: \.self) { sz in
            BearLogoView(size: CGFloat(sz))
        }
    }
    .padding(24)
    .background(Color(hex: "#0D1117") ?? .black)
}

#Preview("App icon") {
    BearIconView(size: 300)
        .padding(20)
        .background(Color(hex: "#0D1117") ?? .black)
}

#Preview("Bear logo no bg") {
    BearLogoView(size: 120, showBackground: false)
        .padding(20)
        .background(Color(hex: "#0D1117") ?? .black)
}
#endif
