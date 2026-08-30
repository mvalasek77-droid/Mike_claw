import SwiftUI

struct WatchfighterCanvas: View {
    var state: WatchfighterState
    var date: Date

    var body: some View {
        Canvas { context, size in
            drawBackground(in: &context, size: size)
            drawFighter(in: &context, fighter: state.opponent, side: .opponent, size: size)
            drawFighter(in: &context, fighter: state.player, side: .player, size: size)
            drawStrikes(in: &context, size: size)
            drawScreenOverlay(in: &context, size: size)
        }
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let palette = arenaPalette(state.chapter)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [
                    palette.skyTop,
                    palette.skyMid,
                    Color(red: 0.015, green: 0.018, blue: 0.025)
                ]),
                startPoint: CGPoint(x: size.width * 0.15, y: 0),
                endPoint: CGPoint(x: size.width * 0.86, y: size.height)
            )
        )

        let time = date.timeIntervalSinceReferenceDate
        let shimmer = CGFloat((sin(time * 2.1) + 1) * 0.5)

        var skyline = Path()
        skyline.move(to: CGPoint(x: 0, y: size.height * 0.52))
        for index in 0...9 {
            let x = CGFloat(index) / 9 * size.width
            let y = size.height * (0.38 + CGFloat((index * 7) % 5) * 0.025)
            skyline.addLine(to: CGPoint(x: x, y: y))
            skyline.addLine(to: CGPoint(x: x + size.width * 0.04, y: size.height * 0.54))
        }
        skyline.addLine(to: CGPoint(x: size.width, y: size.height * 0.69))
        skyline.addLine(to: CGPoint(x: 0, y: size.height * 0.69))
        skyline.closeSubpath()
        context.fill(skyline, with: .color(palette.shadow.opacity(0.78)))

        let gateY = size.height * 0.29
        let pillarWidth = max(8, size.width * 0.075)
        let leftPillar = CGRect(x: size.width * 0.08, y: gateY, width: pillarWidth, height: size.height * 0.37)
        let rightPillar = CGRect(x: size.width * 0.84, y: gateY, width: pillarWidth, height: size.height * 0.37)
        context.fill(Path(roundedRect: leftPillar, cornerRadius: 2), with: .color(palette.stone.opacity(0.72)))
        context.fill(Path(roundedRect: rightPillar, cornerRadius: 2), with: .color(palette.stone.opacity(0.72)))
        context.fill(
            Path(roundedRect: CGRect(x: size.width * 0.13, y: gateY - size.height * 0.045, width: size.width * 0.74, height: size.height * 0.052), cornerRadius: 2),
            with: .color(palette.stone.opacity(0.82))
        )

        for index in 0..<4 {
            let side: CGFloat = index < 2 ? -1 : 1
            let x = side < 0 ? size.width * (0.18 + CGFloat(index) * 0.08) : size.width * (0.76 - CGFloat(index - 2) * 0.08)
            let y = size.height * (0.31 + CGFloat(index % 2) * 0.08)
            let flame = CGRect(x: x - 3, y: y - 5, width: 6, height: 10)
            context.fill(Path(ellipseIn: flame.insetBy(dx: -2, dy: -2)), with: .color(palette.fire.opacity(0.24 + Double(shimmer) * 0.20)))
            context.fill(Path(ellipseIn: flame), with: .color(palette.fire.opacity(0.86)))
            context.fill(Path(ellipseIn: flame.insetBy(dx: 2, dy: 3)), with: .color(.white.opacity(0.44)))
        }

        let signRect = CGRect(x: size.width * 0.30, y: size.height * 0.15, width: size.width * 0.40, height: size.height * 0.058)
        context.fill(Path(roundedRect: signRect, cornerRadius: 3), with: .color(.black.opacity(0.52)))
        context.stroke(Path(roundedRect: signRect, cornerRadius: 3), with: .color(palette.accent.opacity(0.54)), lineWidth: 1)
        context.draw(
            Text(state.chapter.arenaTag)
                .font(.system(size: max(7, size.width * 0.05), weight: .black, design: .rounded))
                .foregroundStyle(palette.accent.opacity(0.88)),
            at: CGPoint(x: signRect.midX, y: signRect.midY),
            anchor: .center
        )

        drawArenaSetPieces(in: &context, size: size, palette: palette)

        if state.chapter == .cinderGate || state.finisherTimer > 0 {
            drawHellLandscape(in: &context, size: size)
        }

        let floorTop = size.height * 0.67
        let floorRect = CGRect(x: 0, y: floorTop, width: size.width, height: size.height - floorTop)
        context.fill(
            Path(floorRect),
            with: .linearGradient(
                Gradient(colors: [palette.floor.opacity(0.88), .black.opacity(0.97)]),
                startPoint: CGPoint(x: 0, y: floorTop),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        var ropes = Path()
        for yFactor in [CGFloat(0.23), CGFloat(0.32), CGFloat(0.41)] {
            ropes.move(to: CGPoint(x: size.width * 0.08, y: size.height * yFactor))
            ropes.addLine(to: CGPoint(x: size.width * 0.92, y: size.height * yFactor))
        }
        context.stroke(ropes, with: .color(palette.accent.opacity(0.25)), lineWidth: 1.4)

        var grid = Path()
        for index in 0..<8 {
            let y = floorTop + CGFloat(index) * size.height * 0.048
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        for index in 0..<7 {
            let x = size.width * (0.02 + CGFloat(index) * 0.17)
            grid.move(to: CGPoint(x: x, y: floorTop))
            grid.addLine(to: CGPoint(x: x + size.width * 0.17, y: size.height))
        }
        context.stroke(grid, with: .color(palette.line.opacity(0.18)), lineWidth: 1)

        var crowd = Path()
        for index in 0..<20 {
            let x = CGFloat(index) / 19 * size.width
            let y = size.height * (0.585 + CGFloat((index * 5) % 3) * 0.012)
            crowd.addEllipse(in: CGRect(x: x - 3, y: y - 5, width: 6, height: 7))
            crowd.addRect(CGRect(x: x - 3, y: y, width: 6, height: 10))
        }
        context.fill(crowd, with: .color(.black.opacity(0.46)))
    }

    private func drawFighter(in context: inout GraphicsContext, fighter: DuelFighter, side: FighterSide, size: CGSize) {
        let baseAnchor = point(x: fighter.x, y: fighter.y, size: size)
        let unit = min(size.width, size.height)
        let breathing = CGFloat(sin(date.timeIntervalSinceReferenceDate * 7.5 + Double(side == .player ? 0 : 1))) * unit * 0.004
        let lunge = actionLunge(for: fighter.action) * fighter.facing * unit
        let recoil = fighter.action == .hit ? -fighter.facing * unit * 0.018 : 0
        let jumpLift = fighter.action == .jumpKick ? -unit * 0.115 : 0
        let crouchDrop = fighter.action == .crouch ? unit * 0.036 : 0
        let anchor = CGPoint(x: baseAnchor.x + lunge + recoil, y: baseAnchor.y + breathing + jumpLift + crouchDrop)
        let sprite = DigitizedSprite(
            imageName: fighter.archetype.imageName,
            aspectRatio: fighter.archetype.aspectRatio,
            heightFactor: fighter.archetype.heightFactor,
            footOffset: fighter.archetype.footOffset
        )

        if fighter.action == .special || fighter.action == .projectile {
            drawSpecialAura(in: &context, anchor: anchor, fighter: fighter, size: size)
        }

        if fighter.action == .blocking {
            drawGuard(in: &context, anchor: anchor, fighter: fighter, size: size)
        }

        if fighter.archetype.usesBitmapSprite {
            drawDigitizedSprite(
                in: &context,
                sprite: sprite,
                anchor: anchor,
                facing: fighter.facing,
                size: size,
                action: fighter.action,
                defeated: fighter.action == .defeated
            )
        } else {
            drawProceduralFighter(in: &context, fighter: fighter, anchor: anchor, size: size)
        }

        drawActionMotion(in: &context, anchor: anchor, fighter: fighter, size: size)

        if fighter.action == .victory {
            let tagPoint = CGPoint(x: anchor.x, y: anchor.y - min(size.width, size.height) * fighter.archetype.heightFactor * 0.54)
            context.draw(
                Text("WINS")
                    .font(.system(size: max(8, size.width * 0.044), weight: .black, design: .rounded))
                    .foregroundStyle(Color.watchfighterGold),
                at: tagPoint,
                anchor: .center
            )
        }
    }

    private func drawSpecialAura(in context: inout GraphicsContext, anchor: CGPoint, fighter: DuelFighter, size: CGSize) {
        let unit = min(size.width, size.height) * 0.16
        let palette = styleAccent(for: fighter.archetype)
        let aura = CGRect(x: anchor.x - unit * 0.7, y: anchor.y - unit * 1.95, width: unit * 1.4, height: unit * 2.35)
        context.fill(Path(ellipseIn: aura), with: .color(palette.opacity(0.16)))
        context.stroke(Path(ellipseIn: aura.insetBy(dx: unit * 0.12, dy: unit * 0.12)), with: .color(palette.opacity(0.42)), lineWidth: 1.2)

        var trail = Path()
        let startX = anchor.x - fighter.facing * unit * 1.1
        trail.move(to: CGPoint(x: startX, y: anchor.y - unit * 0.85))
        trail.addLine(to: CGPoint(x: anchor.x + fighter.facing * unit * 1.4, y: anchor.y - unit * 0.55))
        trail.addLine(to: CGPoint(x: anchor.x + fighter.facing * unit * 1.1, y: anchor.y - unit * 0.05))
        trail.addLine(to: CGPoint(x: startX, y: anchor.y + unit * 0.10))
        trail.closeSubpath()
        context.fill(trail, with: .linearGradient(
            Gradient(colors: [palette.opacity(0.05), palette.opacity(0.34), .white.opacity(0.18)]),
            startPoint: CGPoint(x: startX, y: anchor.y),
            endPoint: CGPoint(x: anchor.x + fighter.facing * unit * 1.4, y: anchor.y)
        ))
    }

    private func drawGuard(in context: inout GraphicsContext, anchor: CGPoint, fighter: DuelFighter, size: CGSize) {
        let unit = min(size.width, size.height) * 0.13
        let shield = CGRect(
            x: anchor.x + fighter.facing * unit * 0.12 - unit * 0.5,
            y: anchor.y - unit * 1.65,
            width: unit,
            height: unit * 1.35
        )
        context.fill(Path(ellipseIn: shield), with: .color(Color.watchfighterMint.opacity(0.12)))
        context.stroke(Path(ellipseIn: shield), with: .color(Color.watchfighterMint.opacity(0.48)), lineWidth: 1.4)
    }

    private func drawStrikes(in context: inout GraphicsContext, size: CGSize) {
        for strike in state.strikes {
            let center = point(x: strike.x, y: strike.y, size: size)
            let progress = CGFloat(strike.age / strike.lifetime).clamped(to: 0...1)
            let base = min(size.width, size.height)
            let radius = base * (strike.kind == .round ? 0.17 : 0.055) * (0.35 + progress)
            let color: Color
            switch strike.kind {
            case .hit:
                color = .watchfighterGold
            case .blocked:
                color = .white
            case .special:
                color = strike.side == .player ? styleAccent(for: state.player.archetype) : styleAccent(for: state.opponent.archetype)
            case .projectile:
                color = strike.side == .player ? styleAccent(for: state.player.archetype) : styleAccent(for: state.opponent.archetype)
            case .throwImpact:
                color = .watchfighterGold
            case .blood:
                color = .watchfighterRed
            case .round:
                color = .watchfighterRed
            case .finisher:
                color = .watchfighterGold
            case .headPop, .bodyBurst, .armDrop:
                color = .watchfighterRed
            }

            if strike.kind == .blood {
                let spray = max(2, radius * 0.26)
                for index in 0..<5 {
                    let offset = CGFloat(index - 2) * spray * 0.55
                    let drop = CGRect(
                        x: center.x + offset - spray * 0.22,
                        y: center.y + CGFloat(index % 2) * spray * 0.35 - spray * 0.22,
                        width: spray * 0.44,
                        height: spray * 0.32
                    )
                    context.fill(Path(ellipseIn: drop), with: .color(Color.watchfighterRed.opacity(Double(1 - progress) * 0.75)))
                }
                continue
            }

            if strike.kind == .headPop || strike.kind == .bodyBurst || strike.kind == .armDrop {
                drawFinisherEffect(in: &context, center: center, radius: radius, progress: progress, kind: strike.kind)
                continue
            }

            if strike.kind == .projectile {
                let orb = CGRect(x: center.x - radius * 0.72, y: center.y - radius * 0.72, width: radius * 1.44, height: radius * 1.44)
                context.fill(Path(ellipseIn: orb), with: .color(color.opacity(Double(1 - progress) * 0.55)))
                context.stroke(Path(ellipseIn: orb.insetBy(dx: -radius * 0.22, dy: -radius * 0.22)), with: .color(.white.opacity(Double(1 - progress) * 0.45)), lineWidth: max(1, radius * 0.16))
                continue
            }

            if strike.kind == .blocked {
                context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color.opacity(Double(1 - progress) * 0.7)), lineWidth: 1.4)
                continue
            }

            var burst = Path()
            for index in 0..<10 {
                let angle = CGFloat(index) * .pi / 5
                let inner = radius * 0.15
                let outer = radius * (0.78 + CGFloat(index % 2) * 0.22)
                burst.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                burst.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            }
            context.stroke(burst, with: .color(color.opacity(Double(1 - progress))), lineWidth: max(1, 3.2 * (1 - progress)))
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.20, y: center.y - radius * 0.20, width: radius * 0.40, height: radius * 0.40)), with: .color(.white.opacity(Double(1 - progress) * 0.55)))
        }
    }

    private func drawScreenOverlay(in context: inout GraphicsContext, size: CGSize) {
        var scanlines = Path()
        var y: CGFloat = 0
        while y < size.height {
            scanlines.move(to: CGPoint(x: 0, y: y.rounded(.down)))
            scanlines.addLine(to: CGPoint(x: size.width, y: y.rounded(.down)))
            y += 4
        }
        context.stroke(scanlines, with: .color(.black.opacity(0.16)), lineWidth: 1)

        let top = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.18)
        let bottom = CGRect(x: 0, y: size.height * 0.82, width: size.width, height: size.height * 0.18)
        context.fill(
            Path(top),
            with: .linearGradient(
                Gradient(colors: [.black.opacity(0.46), .black.opacity(0)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: top.maxY)
            )
        )
        context.fill(
            Path(bottom),
            with: .linearGradient(
                Gradient(colors: [.black.opacity(0), .black.opacity(0.48)]),
                startPoint: CGPoint(x: 0, y: bottom.minY),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        let left = CGRect(x: 0, y: 0, width: size.width * 0.10, height: size.height)
        let right = CGRect(x: size.width * 0.90, y: 0, width: size.width * 0.10, height: size.height)
        context.fill(Path(left), with: .linearGradient(Gradient(colors: [.black.opacity(0.36), .black.opacity(0)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: left.maxX, y: 0)))
        context.fill(Path(right), with: .linearGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0.36)]), startPoint: CGPoint(x: right.minX, y: 0), endPoint: CGPoint(x: size.width, y: 0)))

        if state.finisherTimer > 0 {
            context.draw(
                Text(state.finisherText)
                    .font(.system(size: max(17, size.width * 0.078), weight: .black, design: .rounded))
                    .foregroundStyle(Color.watchfighterRed),
                at: CGPoint(x: size.width * 0.5, y: size.height * 0.56),
                anchor: .center
            )
        }
    }

    private func drawFinisherEffect(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, progress: CGFloat, kind: StrikeKind) {
        let fade = Double(1 - progress)
        let red = Color.watchfighterRed.opacity(fade * 0.82)
        let gold = Color.watchfighterGold.opacity(fade * 0.70)
        let chunkCount = kind == .bodyBurst ? 12 : 7

        for index in 0..<chunkCount {
            let angle = CGFloat(index) / CGFloat(chunkCount) * .pi * 2 + progress * .pi
            let distance = radius * (0.7 + progress * 3.6) * (index.isMultiple(of: 2) ? 1.0 : 0.66)
            let chunkCenter = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
            let size = max(3, radius * (kind == .armDrop ? 0.34 : 0.25))
            let rect = CGRect(x: chunkCenter.x - size * 0.5, y: chunkCenter.y - size * 0.5, width: size, height: size * (kind == .armDrop ? 1.55 : 1.0))
            context.fill(Path(roundedRect: rect, cornerRadius: size * 0.18), with: .color(index.isMultiple(of: 3) ? gold : red))
            context.stroke(Path(roundedRect: rect, cornerRadius: size * 0.18), with: .color(.black.opacity(fade * 0.55)), lineWidth: 1)
        }

        if kind == .headPop {
            let head = CGRect(x: center.x - radius * 0.46, y: center.y - radius * (1.15 + progress * 2.1), width: radius * 0.92, height: radius * 0.92)
            context.fill(Path(ellipseIn: head), with: .color(Color.watchfighterGold.opacity(fade * 0.9)))
            context.stroke(Path(ellipseIn: head), with: .color(Color.watchfighterRed.opacity(fade * 0.85)), lineWidth: max(1, radius * 0.10))
        } else if kind == .armDrop {
            let arm = CGRect(x: center.x + radius * (0.45 + progress), y: center.y + radius * (0.45 + progress * 1.7), width: radius * 0.42, height: radius * 1.6)
            context.fill(Path(roundedRect: arm, cornerRadius: radius * 0.18), with: .color(Color.watchfighterRed.opacity(fade * 0.82)))
            context.fill(Path(ellipseIn: arm.offsetBy(dx: radius * 0.04, dy: radius * 1.34)), with: .color(Color.watchfighterGold.opacity(fade * 0.78)))
        } else {
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(Color.watchfighterRed.opacity(fade * 0.28)))
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius * 1.4, y: center.y - radius * 1.4, width: radius * 2.8, height: radius * 2.8)), with: .color(Color.watchfighterGold.opacity(fade * 0.65)), lineWidth: max(2, radius * 0.15))
        }
    }

    private func drawArenaSetPieces(in context: inout GraphicsContext, size: CGSize, palette: ArenaPalette) {
        switch state.chapter {
        case .pirateCove:
            var mast = Path()
            mast.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.24))
            mast.addLine(to: CGPoint(x: size.width * 0.18, y: size.height * 0.58))
            mast.move(to: CGPoint(x: size.width * 0.10, y: size.height * 0.32))
            mast.addLine(to: CGPoint(x: size.width * 0.32, y: size.height * 0.39))
            context.stroke(mast, with: .color(palette.accent.opacity(0.42)), lineWidth: 2)
            context.fill(Path(roundedRect: CGRect(x: size.width * 0.54, y: size.height * 0.40, width: size.width * 0.28, height: size.height * 0.07), cornerRadius: 4), with: .color(.black.opacity(0.36)))
        case .dragonAlley:
            for index in 0..<5 {
                let x = size.width * (0.18 + CGFloat(index) * 0.16)
                let lantern = CGRect(x: x - 5, y: size.height * 0.24, width: 10, height: 13)
                context.fill(Path(roundedRect: lantern, cornerRadius: 3), with: .color(Color.watchfighterRed.opacity(0.55)))
                context.stroke(Path(roundedRect: lantern, cornerRadius: 3), with: .color(Color.watchfighterGold.opacity(0.55)), lineWidth: 1)
            }
        case .sunPier:
            let water = CGRect(x: 0, y: size.height * 0.46, width: size.width, height: size.height * 0.12)
            context.fill(Path(water), with: .linearGradient(Gradient(colors: [Color.watchfighterMint.opacity(0.20), .black.opacity(0)]), startPoint: water.origin, endPoint: CGPoint(x: 0, y: water.maxY)))
            context.fill(Path(roundedRect: CGRect(x: size.width * 0.76, y: size.height * 0.34, width: size.width * 0.12, height: size.height * 0.09), cornerRadius: 3), with: .color(Color.watchfighterRed.opacity(0.42)))
        case .runwayTerminal, .redCarpet:
            for index in 0..<6 {
                let x = size.width * (0.12 + CGFloat(index) * 0.15)
                let light = CGRect(x: x, y: size.height * 0.43, width: 5, height: 5)
                context.fill(Path(ellipseIn: light), with: .color(Color(red: 1.0, green: 0.45, blue: 0.78).opacity(0.75)))
            }
            context.fill(Path(roundedRect: CGRect(x: size.width * 0.18, y: size.height * 0.57, width: size.width * 0.64, height: size.height * 0.04), cornerRadius: 2), with: .color(Color.watchfighterRed.opacity(0.24)))
        case .blackoutBase:
            for index in 0..<4 {
                let x = size.width * (0.18 + CGFloat(index) * 0.20)
                context.stroke(Path(ellipseIn: CGRect(x: x, y: size.height * 0.30, width: 18, height: 7)), with: .color(Color.watchfighterMint.opacity(0.35)), lineWidth: 1.5)
            }
        case .launchFoundry:
            var rocket = Path()
            rocket.move(to: CGPoint(x: size.width * 0.78, y: size.height * 0.22))
            rocket.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.40))
            rocket.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.40))
            rocket.closeSubpath()
            context.fill(rocket, with: .color(.white.opacity(0.16)))
            context.stroke(rocket, with: .color(palette.accent.opacity(0.48)), lineWidth: 1)
        case .goldRally:
            for index in 0..<4 {
                let rect = CGRect(x: size.width * (0.10 + CGFloat(index) * 0.22), y: size.height * 0.36, width: size.width * 0.12, height: size.height * 0.04)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Color.watchfighterGold.opacity(0.28)))
            }
        case .icePalace:
            for index in 0..<5 {
                let x = size.width * (0.12 + CGFloat(index) * 0.19)
                var shard = Path()
                shard.move(to: CGPoint(x: x, y: size.height * 0.58))
                shard.addLine(to: CGPoint(x: x + 12, y: size.height * 0.39))
                shard.addLine(to: CGPoint(x: x + 24, y: size.height * 0.58))
                shard.closeSubpath()
                context.fill(shard, with: .color(Color(red: 0.70, green: 0.92, blue: 1.0).opacity(0.18)))
            }
        case .cageNight:
            var mesh = Path()
            for index in 0..<9 {
                let x = CGFloat(index) / 8 * size.width
                mesh.move(to: CGPoint(x: x, y: size.height * 0.28))
                mesh.addLine(to: CGPoint(x: x + size.width * 0.24, y: size.height * 0.66))
                mesh.move(to: CGPoint(x: x, y: size.height * 0.66))
                mesh.addLine(to: CGPoint(x: x + size.width * 0.24, y: size.height * 0.28))
            }
            context.stroke(mesh, with: .color(.white.opacity(0.10)), lineWidth: 1)
        case .obsidianThrone:
            let throne = CGRect(x: size.width * 0.38, y: size.height * 0.31, width: size.width * 0.24, height: size.height * 0.25)
            context.fill(Path(roundedRect: throne, cornerRadius: 5), with: .color(.black.opacity(0.40)))
            context.stroke(Path(roundedRect: throne, cornerRadius: 5), with: .color(Color.watchfighterGold.opacity(0.35)), lineWidth: 1.2)
        case .millionRoom:
            for index in 0..<3 {
                let x = size.width * (0.22 + CGFloat(index) * 0.25)
                context.fill(Path(roundedRect: CGRect(x: x, y: size.height * 0.30, width: 18, height: 52), cornerRadius: 8), with: .color(Color.watchfighterRed.opacity(0.28)))
                context.stroke(Path(roundedRect: CGRect(x: x, y: size.height * 0.30, width: 18, height: 52), cornerRadius: 8), with: .color(Color.watchfighterGold.opacity(0.22)), lineWidth: 1)
            }
        default:
            break
        }
    }

    private func drawHellLandscape(in context: inout GraphicsContext, size: CGSize) {
        let time = CGFloat(date.timeIntervalSinceReferenceDate)
        let horizon = size.height * 0.58

        let inferno = CGRect(x: 0, y: size.height * 0.28, width: size.width, height: size.height * 0.40)
        context.fill(
            Path(inferno),
            with: .linearGradient(
                Gradient(colors: [
                    Color.black.opacity(0),
                    Color(red: 0.42, green: 0.015, blue: 0.005).opacity(0.72),
                    Color(red: 1.0, green: 0.16, blue: 0.015).opacity(0.88)
                ]),
                startPoint: CGPoint(x: size.width * 0.5, y: inferno.minY),
                endPoint: CGPoint(x: size.width * 0.5, y: inferno.maxY)
            )
        )

        var cliffs = Path()
        cliffs.move(to: CGPoint(x: 0, y: horizon))
        for index in 0...12 {
            let x = CGFloat(index) / 12 * size.width
            let peak = CGFloat((index * 11) % 5)
            cliffs.addLine(to: CGPoint(x: x, y: horizon - size.height * (0.05 + peak * 0.018)))
        }
        cliffs.addLine(to: CGPoint(x: size.width, y: size.height * 0.69))
        cliffs.addLine(to: CGPoint(x: 0, y: size.height * 0.69))
        cliffs.closeSubpath()
        context.fill(cliffs, with: .color(Color(red: 0.055, green: 0.008, blue: 0.006).opacity(0.92)))
        context.stroke(cliffs, with: .color(Color.watchfighterRed.opacity(0.58)), lineWidth: 1.2)

        for index in 0..<11 {
            let phase = time * (4.2 + CGFloat(index % 3) * 0.55) + CGFloat(index) * 1.7
            let sway = sin(phase) * size.width * 0.012
            let x = size.width * (0.04 + CGFloat(index) * 0.092)
            let flameHeight = size.height * (0.10 + CGFloat((index * 7) % 4) * 0.025)
            let baseY = size.height * 0.69

            var flame = Path()
            flame.move(to: CGPoint(x: x - size.width * 0.035, y: baseY))
            flame.addQuadCurve(
                to: CGPoint(x: x + sway, y: baseY - flameHeight),
                control: CGPoint(x: x - size.width * 0.015 + sway, y: baseY - flameHeight * 0.48)
            )
            flame.addQuadCurve(
                to: CGPoint(x: x + size.width * 0.035, y: baseY),
                control: CGPoint(x: x + size.width * 0.025 + sway, y: baseY - flameHeight * 0.42)
            )
            flame.closeSubpath()
            context.fill(flame, with: .linearGradient(
                Gradient(colors: [Color.watchfighterGold, Color(red: 1.0, green: 0.08, blue: 0.01), .black.opacity(0.12)]),
                startPoint: CGPoint(x: x, y: baseY),
                endPoint: CGPoint(x: x + sway, y: baseY - flameHeight)
            ))
        }

        var lava = Path()
        lava.move(to: CGPoint(x: 0, y: size.height * 0.655))
        for index in 0...8 {
            let x = CGFloat(index) / 8 * size.width
            let ripple = sin(time * 2.8 + CGFloat(index)) * size.height * 0.008
            lava.addLine(to: CGPoint(x: x, y: size.height * 0.655 + ripple))
        }
        context.stroke(lava, with: .color(Color.watchfighterRed.opacity(0.62)), lineWidth: 5.4)
        context.stroke(lava, with: .color(Color.watchfighterGold.opacity(0.90)), lineWidth: 2.2)
    }

    private func arenaPalette(_ chapter: StoryChapter) -> ArenaPalette {
        switch chapter {
        case .cinderGate:
            return ArenaPalette(
                skyTop: Color(red: 0.045, green: 0.035, blue: 0.040),
                skyMid: Color(red: 0.30, green: 0.07, blue: 0.05),
                floor: Color(red: 0.12, green: 0.08, blue: 0.07),
                stone: Color(red: 0.27, green: 0.20, blue: 0.17),
                line: Color.watchfighterGold,
                accent: Color.watchfighterGold,
                fire: Color(red: 1.0, green: 0.28, blue: 0.10),
                shadow: Color(red: 0.03, green: 0.02, blue: 0.025)
            )
        case .neonRooftop:
            return ArenaPalette(
                skyTop: Color(red: 0.025, green: 0.045, blue: 0.070),
                skyMid: Color(red: 0.03, green: 0.20, blue: 0.22),
                floor: Color(red: 0.045, green: 0.11, blue: 0.13),
                stone: Color(red: 0.10, green: 0.24, blue: 0.25),
                line: Color.watchfighterMint,
                accent: Color(red: 1.0, green: 0.30, blue: 0.58),
                fire: Color.watchfighterMint,
                shadow: Color(red: 0.01, green: 0.025, blue: 0.035)
            )
        case .stormBridge:
            return ArenaPalette(
                skyTop: Color(red: 0.035, green: 0.050, blue: 0.075),
                skyMid: Color(red: 0.10, green: 0.12, blue: 0.18),
                floor: Color(red: 0.07, green: 0.10, blue: 0.12),
                stone: Color(red: 0.16, green: 0.19, blue: 0.22),
                line: Color(red: 0.70, green: 0.90, blue: 1.0),
                accent: Color.watchfighterGold,
                fire: Color(red: 0.66, green: 0.88, blue: 1.0),
                shadow: Color(red: 0.015, green: 0.020, blue: 0.030)
            )
        case .obsidianThrone:
            return ArenaPalette(
                skyTop: Color(red: 0.018, green: 0.015, blue: 0.020),
                skyMid: Color(red: 0.17, green: 0.025, blue: 0.050),
                floor: Color(red: 0.08, green: 0.055, blue: 0.075),
                stone: Color(red: 0.18, green: 0.14, blue: 0.18),
                line: Color.watchfighterRed,
                accent: Color.watchfighterGold,
                fire: Color.watchfighterRed,
                shadow: Color(red: 0.01, green: 0.01, blue: 0.015)
            )
        case .pirateCove:
            return ArenaPalette(
                skyTop: Color(red: 0.015, green: 0.050, blue: 0.070),
                skyMid: Color(red: 0.03, green: 0.18, blue: 0.22),
                floor: Color(red: 0.08, green: 0.07, blue: 0.055),
                stone: Color(red: 0.22, green: 0.15, blue: 0.10),
                line: Color.watchfighterGold,
                accent: Color(red: 0.36, green: 0.80, blue: 0.88),
                fire: Color.watchfighterGold,
                shadow: Color(red: 0.01, green: 0.025, blue: 0.035)
            )
        case .dragonAlley:
            return ArenaPalette(
                skyTop: Color(red: 0.06, green: 0.015, blue: 0.025),
                skyMid: Color(red: 0.22, green: 0.03, blue: 0.06),
                floor: Color(red: 0.09, green: 0.045, blue: 0.05),
                stone: Color(red: 0.18, green: 0.08, blue: 0.09),
                line: Color.watchfighterRed,
                accent: Color.watchfighterGold,
                fire: Color.watchfighterRed,
                shadow: Color(red: 0.02, green: 0.01, blue: 0.015)
            )
        case .sunPier:
            return ArenaPalette(
                skyTop: Color(red: 0.02, green: 0.16, blue: 0.22),
                skyMid: Color(red: 0.96, green: 0.23, blue: 0.24),
                floor: Color(red: 0.10, green: 0.08, blue: 0.06),
                stone: Color(red: 0.22, green: 0.17, blue: 0.12),
                line: Color.watchfighterMint,
                accent: Color.watchfighterGold,
                fire: Color(red: 1.0, green: 0.42, blue: 0.14),
                shadow: Color(red: 0.015, green: 0.025, blue: 0.03)
            )
        case .runwayTerminal, .redCarpet:
            return ArenaPalette(
                skyTop: Color(red: 0.035, green: 0.025, blue: 0.055),
                skyMid: Color(red: 0.26, green: 0.05, blue: 0.16),
                floor: Color(red: 0.045, green: 0.045, blue: 0.060),
                stone: Color(red: 0.16, green: 0.12, blue: 0.18),
                line: Color(red: 1.0, green: 0.45, blue: 0.78),
                accent: Color.watchfighterGold,
                fire: Color(red: 1.0, green: 0.45, blue: 0.78),
                shadow: Color(red: 0.015, green: 0.012, blue: 0.02)
            )
        case .blackoutBase:
            return ArenaPalette(
                skyTop: Color(red: 0.02, green: 0.035, blue: 0.030),
                skyMid: Color(red: 0.05, green: 0.10, blue: 0.08),
                floor: Color(red: 0.035, green: 0.050, blue: 0.045),
                stone: Color(red: 0.10, green: 0.16, blue: 0.14),
                line: Color.watchfighterMint,
                accent: Color.watchfighterMint,
                fire: Color.watchfighterMint,
                shadow: Color(red: 0.01, green: 0.018, blue: 0.015)
            )
        case .launchFoundry:
            return ArenaPalette(
                skyTop: Color(red: 0.035, green: 0.040, blue: 0.060),
                skyMid: Color(red: 0.18, green: 0.12, blue: 0.07),
                floor: Color(red: 0.08, green: 0.075, blue: 0.070),
                stone: Color(red: 0.17, green: 0.16, blue: 0.17),
                line: Color(red: 0.66, green: 0.86, blue: 1.0),
                accent: Color.watchfighterGold,
                fire: Color(red: 1.0, green: 0.33, blue: 0.10),
                shadow: Color(red: 0.015, green: 0.018, blue: 0.025)
            )
        case .goldRally:
            return ArenaPalette(
                skyTop: Color(red: 0.055, green: 0.040, blue: 0.015),
                skyMid: Color(red: 0.31, green: 0.18, blue: 0.04),
                floor: Color(red: 0.10, green: 0.075, blue: 0.030),
                stone: Color(red: 0.24, green: 0.18, blue: 0.08),
                line: Color.watchfighterGold,
                accent: Color.watchfighterRed,
                fire: Color.watchfighterGold,
                shadow: Color(red: 0.02, green: 0.014, blue: 0.006)
            )
        case .icePalace:
            return ArenaPalette(
                skyTop: Color(red: 0.020, green: 0.040, blue: 0.075),
                skyMid: Color(red: 0.08, green: 0.16, blue: 0.22),
                floor: Color(red: 0.055, green: 0.085, blue: 0.110),
                stone: Color(red: 0.12, green: 0.18, blue: 0.24),
                line: Color(red: 0.70, green: 0.92, blue: 1.0),
                accent: Color.watchfighterMint,
                fire: Color(red: 0.66, green: 0.88, blue: 1.0),
                shadow: Color(red: 0.010, green: 0.020, blue: 0.035)
            )
        case .cageNight:
            return ArenaPalette(
                skyTop: Color(red: 0.020, green: 0.020, blue: 0.025),
                skyMid: Color(red: 0.10, green: 0.10, blue: 0.12),
                floor: Color(red: 0.055, green: 0.055, blue: 0.060),
                stone: Color(red: 0.14, green: 0.14, blue: 0.16),
                line: Color.watchfighterRed,
                accent: Color.watchfighterMint,
                fire: Color.watchfighterRed,
                shadow: Color(red: 0.01, green: 0.01, blue: 0.014)
            )
        case .millionRoom:
            return ArenaPalette(
                skyTop: Color(red: 0.010, green: 0.010, blue: 0.012),
                skyMid: Color(red: 0.09, green: 0.025, blue: 0.030),
                floor: Color(red: 0.075, green: 0.060, blue: 0.050),
                stone: Color(red: 0.15, green: 0.10, blue: 0.10),
                line: Color.watchfighterGold,
                accent: Color.watchfighterRed,
                fire: Color.watchfighterRed,
                shadow: Color(red: 0.006, green: 0.006, blue: 0.008)
            )
        }
    }

    private func point(x: CGFloat, y: CGFloat, size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    private func actionLunge(for action: FighterAction) -> CGFloat {
        switch action {
        case .jab:
            return 0.014
        case .kick:
            return 0.026
        case .jumpKick:
            return 0.036
        case .throwAttack:
            return 0.020
        case .projectile:
            return 0.030
        case .special:
            return 0.045
        default:
            return 0
        }
    }

    private func drawDigitizedSprite(
        in context: inout GraphicsContext,
        sprite: DigitizedSprite,
        anchor: CGPoint,
        facing: CGFloat,
        size: CGSize,
        action: FighterAction,
        defeated: Bool
    ) {
        let spriteHeight = min(size.width, size.height) * sprite.heightFactor
        let spriteWidth = spriteHeight * sprite.aspectRatio
        let feetY = anchor.y + spriteHeight * sprite.footOffset
        var rect = CGRect(
            x: anchor.x - spriteWidth / 2,
            y: feetY - spriteHeight,
            width: spriteWidth,
            height: spriteHeight
        )

        if defeated {
            rect = rect.offsetBy(dx: -facing * spriteWidth * 0.08, dy: spriteHeight * 0.08)
        }

        let shadowRect = CGRect(
            x: anchor.x - spriteWidth * 0.40,
            y: feetY - spriteHeight * 0.035,
            width: spriteWidth * 0.80,
            height: max(4, spriteHeight * 0.085)
        )
        context.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(defeated ? 0.38 : 0.68)))

        var spriteContext = context
        spriteContext.addFilter(.shadow(color: .black.opacity(0.88), radius: 2.4, x: 1.4, y: 2.4))

        if defeated {
            spriteContext.opacity = 0.72
        }

        let time = CGFloat(date.timeIntervalSinceReferenceDate)
        let stride = sin(time * 13) * spriteHeight * 0.012
        let lean: Angle
        let xScale: CGFloat
        let yScale: CGFloat
        switch action {
        case .jab:
            lean = .degrees(Double(facing * 3.5))
            xScale = 1.035
            yScale = 0.985
        case .kick, .special, .projectile:
            lean = .degrees(Double(facing * 5.0))
            xScale = 1.055
            yScale = 0.975
        case .jumpKick:
            lean = .degrees(Double(facing * 10.0))
            xScale = 1.12
            yScale = 0.92
        case .throwAttack:
            lean = .degrees(Double(facing * 7.0))
            xScale = 1.08
            yScale = 0.96
        case .crouch:
            lean = .degrees(Double(-facing * 2.0))
            xScale = 1.08
            yScale = 0.74
        case .walk:
            lean = .degrees(Double(facing * sin(time * 12) * 1.8))
            xScale = 1
            yScale = 1 + abs(stride) / max(spriteHeight, 1)
        case .hit:
            lean = .degrees(Double(-facing * 4.5))
            xScale = 1.02
            yScale = 0.98
        default:
            lean = .degrees(0)
            xScale = 1
            yScale = 1
        }

        spriteContext.translateBy(x: rect.midX, y: rect.midY + (action == .walk ? -abs(stride) : 0))
        if facing < 0 {
            spriteContext.scaleBy(x: -1, y: 1)
        }
        spriteContext.rotate(by: lean)
        spriteContext.scaleBy(x: xScale, y: yScale)
        spriteContext.draw(Image(sprite.imageName), in: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height))
    }

    private func drawActionMotion(in context: inout GraphicsContext, anchor: CGPoint, fighter: DuelFighter, size: CGSize) {
        let unit = min(size.width, size.height) * 0.12
        let opacity = fighter.action == .special ? 0.62 : 0.44
        let color = fighter.action == .special ? Color.watchfighterMint : Color.watchfighterGold

        switch fighter.action {
        case .jab:
            let y = anchor.y - unit * 0.85
            let rect = CGRect(
                x: anchor.x + fighter.facing * unit * 0.22 - (fighter.facing < 0 ? unit * 1.15 : 0),
                y: y - unit * 0.08,
                width: unit * 1.15,
                height: unit * 0.16
            )
            context.fill(Path(roundedRect: rect, cornerRadius: unit * 0.08), with: .color(color.opacity(opacity)))
        case .kick:
            var arc = Path()
            let start = CGPoint(x: anchor.x + fighter.facing * unit * 0.15, y: anchor.y - unit * 0.28)
            arc.move(to: start)
            arc.addQuadCurve(
                to: CGPoint(x: anchor.x + fighter.facing * unit * 1.55, y: anchor.y - unit * 0.55),
                control: CGPoint(x: anchor.x + fighter.facing * unit * 0.82, y: anchor.y - unit * 1.02)
            )
            context.stroke(arc, with: .color(color.opacity(opacity)), lineWidth: max(2, unit * 0.10))
        case .jumpKick:
            var arc = Path()
            arc.move(to: CGPoint(x: anchor.x - fighter.facing * unit * 0.30, y: anchor.y - unit * 0.15))
            arc.addQuadCurve(
                to: CGPoint(x: anchor.x + fighter.facing * unit * 1.70, y: anchor.y - unit * 0.52),
                control: CGPoint(x: anchor.x + fighter.facing * unit * 0.65, y: anchor.y - unit * 1.15)
            )
            context.stroke(arc, with: .color(Color.watchfighterGold.opacity(0.56)), lineWidth: max(2.2, unit * 0.11))
        case .throwAttack:
            var grab = Path()
            grab.move(to: CGPoint(x: anchor.x + fighter.facing * unit * 0.18, y: anchor.y - unit * 0.82))
            grab.addLine(to: CGPoint(x: anchor.x + fighter.facing * unit * 1.25, y: anchor.y - unit * 0.72))
            grab.move(to: CGPoint(x: anchor.x + fighter.facing * unit * 0.18, y: anchor.y - unit * 0.38))
            grab.addLine(to: CGPoint(x: anchor.x + fighter.facing * unit * 1.18, y: anchor.y - unit * 0.16))
            context.stroke(grab, with: .color(Color.watchfighterGold.opacity(0.62)), lineWidth: max(2, unit * 0.10))
        case .projectile:
            let projectileColor = styleAccent(for: fighter.archetype)
            let orbCenter = CGPoint(x: anchor.x + fighter.facing * unit * 1.42, y: anchor.y - unit * 0.72)
            let orb = CGRect(x: orbCenter.x - unit * 0.20, y: orbCenter.y - unit * 0.20, width: unit * 0.40, height: unit * 0.40)
            context.fill(Path(ellipseIn: orb), with: .color(projectileColor.opacity(0.58)))
            context.stroke(Path(ellipseIn: orb.insetBy(dx: -unit * 0.09, dy: -unit * 0.09)), with: .color(.white.opacity(0.42)), lineWidth: max(1, unit * 0.05))
        case .special:
            var slash = Path()
            slash.move(to: CGPoint(x: anchor.x - fighter.facing * unit * 0.85, y: anchor.y - unit * 1.45))
            slash.addLine(to: CGPoint(x: anchor.x + fighter.facing * unit * 1.55, y: anchor.y - unit * 0.25))
            slash.addLine(to: CGPoint(x: anchor.x + fighter.facing * unit * 1.20, y: anchor.y + unit * 0.10))
            context.stroke(slash, with: .color(color.opacity(opacity)), lineWidth: max(3, unit * 0.13))
        default:
            return
        }
    }

    private func drawProceduralFighter(in context: inout GraphicsContext, fighter: DuelFighter, anchor: CGPoint, size: CGSize) {
        let profile = ProceduralFighterProfile(archetype: fighter.archetype)
        let unit = min(size.width, size.height) * 0.078 * profile.scale * (fighter.action == .crouch ? 0.82 : 1)
        let time = CGFloat(date.timeIntervalSinceReferenceDate)
        let alpha = fighter.action == .defeated ? 0.70 : 1
        let walk = fighter.action == .walk ? sin(time * 12) * 0.24 : 0
        let punch = fighter.action == .jab ? 0.82 : (fighter.action == .special || fighter.action == .projectile || fighter.action == .throwAttack ? 1.12 : 0)
        let kick = fighter.action == .kick || fighter.action == .jumpKick ? 1.0 : 0
        let recoil = fighter.action == .hit ? -0.28 : 0
        let swagger = profile.glamour ? sin(time * 8) * 0.10 : 0
        let bulk = (profile.armWidth + profile.legWidth) * 0.50
        let shoulderSpread = 0.78 + bulk * 0.38
        let waistSpread = 0.40 + bulk * 0.12

        var fighterContext = context
        fighterContext.opacity = alpha
        fighterContext.addFilter(.shadow(color: .black.opacity(0.86), radius: 2.4, x: 1.4, y: 2.4))

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: anchor.x + (x + recoil + swagger) * fighter.facing * unit, y: anchor.y + y * unit)
        }

        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            let shiftedX = x + recoil + swagger
            let originX = fighter.facing > 0 ? anchor.x + shiftedX * unit : anchor.x - (shiftedX + w) * unit
            return CGRect(x: originX, y: anchor.y + y * unit, width: w * unit, height: h * unit)
        }

        func path(_ points: [CGPoint], close: Bool = false) -> Path {
            guard let first = points.first else { return Path() }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            if close {
                path.closeSubpath()
            }
            return path
        }

        func poly(_ points: [CGPoint], fill: Color, stroke: Color = .black.opacity(0.66)) {
            let shape = path(points, close: true)
            fighterContext.stroke(shape, with: .color(.black.opacity(0.80)), lineWidth: max(1.2, unit * 0.13))
            fighterContext.fill(shape, with: .color(fill))
            fighterContext.stroke(shape, with: .color(stroke), lineWidth: max(0.7, unit * 0.055))
        }

        func plate(
            _ x: CGFloat,
            _ y: CGFloat,
            _ w: CGFloat,
            _ h: CGFloat,
            color: Color,
            corner: CGFloat? = nil,
            shadow: Double = 0.24,
            shine: Double = 0.24
        ) {
            let base = rect(x, y, w, h)
            let radius = corner.map { $0 * unit } ?? min(base.width, base.height) * 0.28
            fighterContext.fill(
                Path(roundedRect: base.insetBy(dx: -unit * 0.035, dy: -unit * 0.035), cornerRadius: radius + unit * 0.035),
                with: .color(.black.opacity(0.72))
            )
            fighterContext.fill(Path(roundedRect: base, cornerRadius: radius), with: .color(color))
            let shadowRect = CGRect(x: base.midX - base.width * 0.06, y: base.minY + base.height * 0.10, width: base.width * 0.52, height: base.height * 0.78)
            fighterContext.fill(Path(roundedRect: shadowRect, cornerRadius: radius * 0.70), with: .color(.black.opacity(shadow)))
            let shineRect = CGRect(x: base.minX + base.width * 0.12, y: base.minY + base.height * 0.14, width: base.width * 0.22, height: base.height * 0.58)
            fighterContext.fill(Path(roundedRect: shineRect, cornerRadius: radius * 0.45), with: .color(.white.opacity(shine)))
        }

        func limb(_ points: [CGPoint], color: Color, width: CGFloat) {
            let shape = path(points)
            let baseWidth = width * unit
            fighterContext.stroke(shape, with: .color(.black.opacity(0.82)), lineWidth: baseWidth + max(2.0, unit * 0.16))
            fighterContext.stroke(shape, with: .color(color), lineWidth: baseWidth + max(0.6, unit * 0.04))

            var shadowContext = fighterContext
            shadowContext.translateBy(x: unit * 0.05, y: unit * 0.07)
            shadowContext.stroke(shape, with: .color(.black.opacity(0.28)), lineWidth: max(1.0, baseWidth * 0.62))

            var highlightContext = fighterContext
            highlightContext.translateBy(x: -unit * 0.05, y: -unit * 0.04)
            highlightContext.stroke(shape, with: .color(.white.opacity(0.24)), lineWidth: max(0.8, baseWidth * 0.30))
        }

        func stripe(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, color: Color) {
            fighterContext.fill(Path(roundedRect: rect(x, y, w, h), cornerRadius: unit * 0.035), with: .color(color))
        }

        let shadowRect = CGRect(x: anchor.x - unit * 2.88, y: anchor.y + unit * 2.70, width: unit * 5.76, height: unit * 0.68)
        context.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(fighter.action == .defeated ? 0.34 : 0.64)))

        let pants = profile.lower
        let bootWidth = max(0.78, profile.legWidth * 1.70)
        let bootHeight = max(0.30, profile.legWidth * 0.82)
        let gloveWidth = max(0.46, profile.armWidth * 1.38)
        let gloveHeight = max(0.34, profile.armWidth * 0.92)

        limb([pt(-0.40, 0.78), pt(-0.78 - walk, 1.58), pt(-1.05 - walk, 2.72)], color: pants, width: profile.legWidth)
        if kick > 0 {
            limb([pt(0.38, 0.82), pt(1.20, 0.35), pt(2.18, 0.20)], color: pants, width: profile.legWidth)
        } else {
            limb([pt(0.38, 0.82), pt(0.86 + walk, 1.58), pt(1.18 + walk, 2.68)], color: pants, width: profile.legWidth)
        }
        plate(-1.38 - walk, 2.54, bootWidth, bootHeight, color: profile.boot, corner: 0.10, shadow: 0.32, shine: 0.16)
        if kick > 0 {
            plate(1.88, 0.04, bootWidth, bootHeight, color: profile.boot, corner: 0.10, shadow: 0.32, shine: 0.16)
        } else {
            plate(0.78 + walk, 2.50, bootWidth, bootHeight, color: profile.boot, corner: 0.10, shadow: 0.32, shine: 0.16)
        }

        poly([
            pt(-shoulderSpread, -1.08), pt(shoulderSpread, -1.10),
            pt(waistSpread + 0.32, 0.22), pt(waistSpread, 1.05),
            pt(-waistSpread, 1.05), pt(-waistSpread - 0.32, 0.18)
        ], fill: profile.upper)
        poly([
            pt(-shoulderSpread * 0.86, -0.96), pt(-shoulderSpread * 0.26, -0.98),
            pt(-waistSpread * 0.18, 0.92), pt(-waistSpread * 0.72, 0.86)
        ], fill: .white.opacity(profile.glamour ? 0.14 : 0.10), stroke: .white.opacity(0.05))
        poly([
            pt(shoulderSpread * 0.18, -0.92), pt(shoulderSpread * 0.82, -0.98),
            pt(waistSpread * 0.78, 0.80), pt(waistSpread * 0.22, 0.96)
        ], fill: .black.opacity(0.20), stroke: .black.opacity(0.05))

        plate(-shoulderSpread - 0.28, -1.08, 0.50 + bulk * 0.30, 0.32 + bulk * 0.10, color: profile.accent.opacity(0.92), corner: 0.12, shadow: 0.18, shine: 0.22)
        plate(shoulderSpread - 0.22, -1.10, 0.50 + bulk * 0.30, 0.32 + bulk * 0.10, color: profile.accent.opacity(0.88), corner: 0.12, shadow: 0.22, shine: 0.20)

        if profile.glamour {
            plate(-0.60, -0.56, 1.20, 0.26, color: profile.accent, corner: 0.06, shadow: 0.20, shine: 0.34)
            stripe(-0.56, 0.62, 1.12, 0.16, color: profile.accent.opacity(0.92))
        } else {
            stripe(-0.66, -0.76, 1.32, 0.18, color: profile.accent.opacity(0.88))
            stripe(-0.48, 0.72, 0.96, 0.16, color: .black.opacity(0.34))
        }

        limb([pt(-0.64, -0.80), pt(-1.18, -0.32), pt(-1.44, 0.34)], color: profile.skin, width: profile.armWidth)
        limb([pt(0.62, -0.82), pt(1.18 + punch, -0.55), pt(1.52 + punch, -0.48)], color: profile.skin, width: profile.armWidth)
        plate(-1.62, 0.12, gloveWidth, gloveHeight, color: profile.accent, corner: 0.12, shadow: 0.30, shine: 0.24)
        plate(1.34 + punch, -0.72, gloveWidth, gloveHeight, color: profile.accent, corner: 0.12, shadow: 0.30, shine: 0.24)

        let faceRect = rect(-0.50, -2.10, 1.00, 1.04)
        fighterContext.fill(Path(ellipseIn: faceRect.insetBy(dx: -unit * 0.035, dy: -unit * 0.035)), with: .color(.black.opacity(0.70)))
        fighterContext.fill(Path(ellipseIn: faceRect), with: .color(profile.skin))
        fighterContext.fill(
            Path(ellipseIn: CGRect(x: faceRect.midX - faceRect.width * 0.05, y: faceRect.midY - faceRect.height * 0.02, width: faceRect.width * 0.48, height: faceRect.height * 0.44)),
            with: .color(.black.opacity(0.16))
        )
        fighterContext.fill(
            Path(ellipseIn: CGRect(x: faceRect.minX + faceRect.width * 0.18, y: faceRect.minY + faceRect.height * 0.16, width: faceRect.width * 0.28, height: faceRect.height * 0.42)),
            with: .color(.white.opacity(0.18))
        )
        fighterContext.stroke(Path(ellipseIn: faceRect), with: .color(.black.opacity(0.58)), lineWidth: max(0.7, unit * 0.08))
        stripe(-0.30, -1.78, 0.20, 0.08, color: .black.opacity(0.88))
        stripe(0.12, -1.78, 0.20, 0.08, color: .black.opacity(0.88))
        stripe(-0.08, -1.64, 0.12, 0.20, color: .black.opacity(0.16))

        if profile.glamour {
            var hairTrail = Path()
            hairTrail.move(to: pt(-0.18, -2.38))
            hairTrail.addCurve(to: pt(-1.30 - swagger, -1.08), control1: pt(-1.05, -2.54), control2: pt(-1.64, -1.90))
            hairTrail.addCurve(to: pt(-0.22, -1.56), control1: pt(-1.12, -1.52), control2: pt(-0.68, -1.72))
            hairTrail.closeSubpath()
            fighterContext.fill(hairTrail, with: .color(profile.hair))
            fighterContext.stroke(hairTrail, with: .color(.black.opacity(0.40)), lineWidth: max(0.7, unit * 0.07))
            fighterContext.fill(Path(ellipseIn: rect(-0.44, -2.30, 0.34, 0.24)), with: .color(.white.opacity(0.12)))
        }

        poly([
            pt(-0.64, -2.08), pt(-0.10, -2.46), pt(0.58, -2.14),
            pt(0.44, -1.76), pt(0.05, -1.92), pt(-0.50, -1.76)
        ], fill: profile.hair, stroke: .black.opacity(0.36))

        switch fighter.archetype {
        case .mara:
            stripe(-0.76, 0.12, 1.44, 0.16, color: Color.watchfighterGold.opacity(0.88))
            var sash = Path()
            sash.move(to: pt(-0.78, 0.28))
            sash.addQuadCurve(to: pt(0.46, 1.12), control: pt(-0.18, 0.78))
            fighterContext.stroke(sash, with: .color(Color.watchfighterRed.opacity(0.72)), lineWidth: max(1.2, unit * 0.10))
            var blade = Path()
            blade.move(to: pt(1.52 + punch, -0.54))
            blade.addQuadCurve(to: pt(2.42 + punch, -1.08), control: pt(2.06 + punch, -0.98))
            fighterContext.stroke(blade, with: .color(.black.opacity(0.82)), lineWidth: max(1.6, unit * 0.09))
            fighterContext.stroke(blade, with: .color(.white.opacity(0.90)), lineWidth: max(1.0, unit * 0.045))
        case .lennox:
            stripe(-0.56, 0.72, 1.12, 0.18, color: Color.watchfighterGold.opacity(0.92))
            stripe(-0.70, -1.88, 1.06, 0.12, color: Color.watchfighterRed.opacity(0.88))
            var dragon = Path()
            dragon.move(to: pt(-0.44, -0.50))
            dragon.addQuadCurve(to: pt(0.38, -0.18), control: pt(0.10, -0.78))
            dragon.addQuadCurve(to: pt(-0.18, 0.18), control: pt(0.62, 0.10))
            fighterContext.stroke(dragon, with: .color(Color.watchfighterRed.opacity(0.82)), lineWidth: max(1.0, unit * 0.065))
        case .sunny:
            stripe(-0.74, -0.42, 1.48, 0.12, color: .white.opacity(0.62))
            stripe(-0.58, 0.32, 1.16, 0.12, color: .white.opacity(0.52))
            stripe(-0.30, -2.32, 0.62, 0.18, color: Color.watchfighterGold.opacity(0.86))
            fighterContext.fill(Path(ellipseIn: rect(-0.22, -2.46, 0.44, 0.24)), with: .color(profile.hair.opacity(0.86)))
        case .nova:
            stripe(-0.48, -1.80, 0.96, 0.14, color: profile.accent.opacity(0.84))
            stripe(-0.44, -0.34, 0.88, 0.12, color: profile.accent.opacity(0.74))
            fighterContext.stroke(Path(ellipseIn: rect(-0.90, -0.98, 0.32, 0.30)), with: .color(profile.accent.opacity(0.82)), lineWidth: max(1.0, unit * 0.055))
            fighterContext.stroke(Path(ellipseIn: rect(0.58, -1.00, 0.32, 0.30)), with: .color(profile.accent.opacity(0.82)), lineWidth: max(1.0, unit * 0.055))
        case .specter:
            stripe(-0.42, -1.80, 0.84, 0.18, color: Color.watchfighterMint.opacity(0.86))
            stripe(-0.54, -0.36, 1.08, 0.14, color: .black.opacity(0.56))
            plate(-0.98, -0.42, 0.30, 1.00, color: Color(red: 0.02, green: 0.03, blue: 0.03), corner: 0.06, shadow: 0.34, shine: 0.08)
            stripe(0.34, 0.88, 0.28, 0.62, color: Color.watchfighterMint.opacity(0.48))
        case .cosmo:
            plate(-1.02, -0.74, 0.34, 1.18, color: Color(red: 0.18, green: 0.20, blue: 0.26), corner: 0.08, shadow: 0.28, shine: 0.22)
            plate(0.72, -0.76, 0.34, 1.18, color: Color(red: 0.18, green: 0.20, blue: 0.26), corner: 0.08, shadow: 0.28, shine: 0.22)
            stripe(-0.54, -0.14, 1.08, 0.12, color: profile.accent.opacity(0.72))
            fighterContext.fill(Path(ellipseIn: rect(-1.00, 0.48, 0.28, 0.34)), with: .color(Color.watchfighterGold.opacity(0.44)))
            fighterContext.fill(Path(ellipseIn: rect(0.74, 0.48, 0.28, 0.34)), with: .color(Color.watchfighterGold.opacity(0.44)))
        case .brass:
            poly([pt(-0.46, -0.90), pt(-0.08, -0.54), pt(-0.22, 0.20), pt(-0.64, -0.22)], fill: .white.opacity(0.22), stroke: .white.opacity(0.04))
            poly([pt(0.44, -0.90), pt(0.08, -0.54), pt(0.20, 0.20), pt(0.62, -0.22)], fill: .black.opacity(0.18), stroke: .black.opacity(0.04))
            stripe(-0.12, -0.98, 0.24, 1.02, color: Color.watchfighterRed)
            fighterContext.fill(Path(ellipseIn: rect(1.66 + punch, -0.72, 0.20, 0.20)), with: .color(Color.watchfighterGold.opacity(0.88)))
        case .volkov:
            fighterContext.stroke(Path(roundedRect: rect(-0.98, -0.96, 1.96, 2.16), cornerRadius: unit * 0.12), with: .color(profile.accent.opacity(0.46)), lineWidth: max(1.8, unit * 0.10))
            fighterContext.fill(Path(ellipseIn: rect(-0.86, -1.24, 0.72, 0.48)), with: .color(.white.opacity(0.32)))
            fighterContext.fill(Path(ellipseIn: rect(0.14, -1.26, 0.72, 0.48)), with: .color(.white.opacity(0.26)))
            stripe(-0.70, -0.30, 1.40, 0.12, color: profile.accent.opacity(0.68))
        case .zara:
            var scarf = Path()
            scarf.move(to: pt(-0.70, -0.78))
            scarf.addCurve(to: pt(1.06, 0.82), control1: pt(-0.46, -0.10), control2: pt(0.72, 0.20))
            fighterContext.stroke(scarf, with: .color(Color.watchfighterGold.opacity(0.72)), lineWidth: max(1.4, unit * 0.12))
            stripe(-0.42, -0.18, 0.84, 0.12, color: .white.opacity(0.46))
            fighterContext.fill(Path(ellipseIn: rect(-0.22, -2.42, 0.44, 0.26)), with: .color(profile.accent.opacity(0.54)))
        case .cage:
            stripe(-0.70, 0.82, 1.40, 0.18, color: Color.watchfighterRed.opacity(0.92))
            stripe(-0.50, -0.48, 1.00, 0.10, color: .white.opacity(0.34))
            fighterContext.stroke(Path(ellipseIn: rect(-1.62, 0.12, gloveWidth, gloveHeight)), with: .color(.white.opacity(0.42)), lineWidth: max(1.0, unit * 0.05))
            fighterContext.stroke(Path(ellipseIn: rect(1.34 + punch, -0.72, gloveWidth, gloveHeight)), with: .color(.white.opacity(0.42)), lineWidth: max(1.0, unit * 0.05))
        case .titan:
            fighterContext.stroke(Path(ellipseIn: rect(-1.34, -0.16, 0.70, 0.60)), with: .color(Color.watchfighterGold), lineWidth: max(1.8, unit * 0.065))
            fighterContext.stroke(Path(ellipseIn: rect(0.74 + punch, -0.86, 0.74, 0.64)), with: .color(Color.watchfighterGold), lineWidth: max(1.8, unit * 0.065))
            stripe(-0.58, -0.62, 1.16, 0.20, color: Color.watchfighterGold.opacity(0.50))
            stripe(-0.62, 0.54, 1.24, 0.18, color: Color.watchfighterRed.opacity(0.54))
        default:
            break
        }

        fighterContext.fill(Path(roundedRect: rect(-0.60, -1.10, 1.34, 0.14), cornerRadius: unit * 0.03), with: .color(.white.opacity(0.13)))
    }

    private func styleAccent(for archetype: FighterArchetype) -> Color {
        switch archetype.combatStyle {
        case .balanced:
            return .watchfighterGold
        case .rushdown:
            return .watchfighterRed
        case .grappler:
            return Color(red: 0.70, green: 0.92, blue: 1.0)
        case .zoner:
            return .watchfighterMint
        case .acrobat:
            return Color(red: 1.0, green: 0.42, blue: 0.82)
        case .bruiser:
            return Color(red: 1.0, green: 0.58, blue: 0.24)
        case .titan:
            return Color(red: 1.0, green: 0.18, blue: 0.20)
        }
    }
}

private struct ArenaPalette {
    var skyTop: Color
    var skyMid: Color
    var floor: Color
    var stone: Color
    var line: Color
    var accent: Color
    var fire: Color
    var shadow: Color
}

private struct DigitizedSprite {
    var imageName: String
    var aspectRatio: CGFloat
    var heightFactor: CGFloat
    var footOffset: CGFloat
}

private struct ProceduralFighterProfile {
    var skin: Color
    var upper: Color
    var lower: Color
    var accent: Color
    var hair: Color
    var boot: Color
    var scale: CGFloat
    var armWidth: CGFloat
    var legWidth: CGFloat
    var glamour: Bool

    init(archetype: FighterArchetype) {
        switch archetype {
        case .mara:
            self.init(
                skin: Color(red: 0.74, green: 0.50, blue: 0.34),
                upper: Color(red: 0.32, green: 0.08, blue: 0.11),
                lower: Color(red: 0.035, green: 0.035, blue: 0.045),
                accent: Color.watchfighterGold,
                hair: Color(red: 0.025, green: 0.018, blue: 0.016),
                boot: Color(red: 0.055, green: 0.035, blue: 0.030),
                scale: 1.0,
                armWidth: 0.26,
                legWidth: 0.34,
                glamour: true
            )
        case .lennox:
            self.init(
                skin: Color(red: 0.78, green: 0.54, blue: 0.36),
                upper: Color(red: 0.05, green: 0.055, blue: 0.045),
                lower: Color(red: 0.83, green: 0.68, blue: 0.16),
                accent: Color.watchfighterRed,
                hair: Color(red: 0.015, green: 0.012, blue: 0.010),
                boot: Color(red: 0.03, green: 0.03, blue: 0.025),
                scale: 0.98,
                armWidth: 0.24,
                legWidth: 0.30,
                glamour: false
            )
        case .sunny:
            self.init(
                skin: Color(red: 0.84, green: 0.58, blue: 0.40),
                upper: Color(red: 0.86, green: 0.06, blue: 0.10),
                lower: Color(red: 0.86, green: 0.06, blue: 0.10),
                accent: Color.watchfighterGold,
                hair: Color(red: 0.94, green: 0.72, blue: 0.28),
                boot: Color(red: 0.08, green: 0.035, blue: 0.035),
                scale: 1.0,
                armWidth: 0.25,
                legWidth: 0.33,
                glamour: true
            )
        case .nova:
            self.init(
                skin: Color(red: 0.70, green: 0.46, blue: 0.33),
                upper: Color(red: 0.04, green: 0.035, blue: 0.06),
                lower: Color(red: 0.055, green: 0.040, blue: 0.070),
                accent: Color(red: 1.0, green: 0.42, blue: 0.82),
                hair: Color(red: 0.04, green: 0.025, blue: 0.030),
                boot: Color(red: 0.030, green: 0.026, blue: 0.038),
                scale: 1.02,
                armWidth: 0.23,
                legWidth: 0.31,
                glamour: true
            )
        case .specter:
            self.init(
                skin: Color(red: 0.66, green: 0.48, blue: 0.34),
                upper: Color(red: 0.045, green: 0.13, blue: 0.10),
                lower: Color(red: 0.035, green: 0.055, blue: 0.050),
                accent: Color.watchfighterMint,
                hair: Color(red: 0.018, green: 0.020, blue: 0.018),
                boot: Color(red: 0.020, green: 0.025, blue: 0.022),
                scale: 1.03,
                armWidth: 0.28,
                legWidth: 0.35,
                glamour: false
            )
        case .cosmo:
            self.init(
                skin: Color(red: 0.78, green: 0.56, blue: 0.42),
                upper: Color(red: 0.10, green: 0.12, blue: 0.17),
                lower: Color(red: 0.055, green: 0.060, blue: 0.075),
                accent: Color(red: 0.65, green: 0.86, blue: 1.0),
                hair: Color(red: 0.09, green: 0.055, blue: 0.035),
                boot: Color(red: 0.035, green: 0.035, blue: 0.045),
                scale: 1.0,
                armWidth: 0.26,
                legWidth: 0.33,
                glamour: false
            )
        case .brass:
            self.init(
                skin: Color(red: 0.86, green: 0.58, blue: 0.38),
                upper: Color(red: 0.82, green: 0.60, blue: 0.12),
                lower: Color(red: 0.07, green: 0.06, blue: 0.06),
                accent: Color.watchfighterRed,
                hair: Color(red: 0.96, green: 0.74, blue: 0.28),
                boot: Color(red: 0.06, green: 0.045, blue: 0.025),
                scale: 1.08,
                armWidth: 0.31,
                legWidth: 0.38,
                glamour: false
            )
        case .volkov:
            self.init(
                skin: Color(red: 0.78, green: 0.58, blue: 0.46),
                upper: Color(red: 0.08, green: 0.12, blue: 0.16),
                lower: Color(red: 0.035, green: 0.048, blue: 0.065),
                accent: Color(red: 0.72, green: 0.92, blue: 1.0),
                hair: Color(red: 0.15, green: 0.12, blue: 0.10),
                boot: Color(red: 0.026, green: 0.032, blue: 0.040),
                scale: 1.04,
                armWidth: 0.29,
                legWidth: 0.35,
                glamour: false
            )
        case .zara:
            self.init(
                skin: Color(red: 0.68, green: 0.45, blue: 0.32),
                upper: Color(red: 0.32, green: 0.03, blue: 0.15),
                lower: Color(red: 0.06, green: 0.035, blue: 0.08),
                accent: Color.watchfighterGold,
                hair: Color(red: 0.05, green: 0.025, blue: 0.020),
                boot: Color(red: 0.035, green: 0.025, blue: 0.045),
                scale: 1.0,
                armWidth: 0.24,
                legWidth: 0.32,
                glamour: true
            )
        case .cage:
            self.init(
                skin: Color(red: 0.76, green: 0.50, blue: 0.34),
                upper: Color(red: 0.15, green: 0.025, blue: 0.030),
                lower: Color(red: 0.025, green: 0.030, blue: 0.038),
                accent: Color.watchfighterRed,
                hair: Color(red: 0.018, green: 0.018, blue: 0.016),
                boot: Color(red: 0.025, green: 0.025, blue: 0.028),
                scale: 1.08,
                armWidth: 0.32,
                legWidth: 0.38,
                glamour: false
            )
        case .titan:
            self.init(
                skin: Color(red: 0.38, green: 0.24, blue: 0.18),
                upper: Color(red: 0.035, green: 0.025, blue: 0.025),
                lower: Color(red: 0.055, green: 0.040, blue: 0.035),
                accent: Color.watchfighterGold,
                hair: Color(red: 0.010, green: 0.010, blue: 0.010),
                boot: Color(red: 0.020, green: 0.018, blue: 0.016),
                scale: 1.86,
                armWidth: 0.62,
                legWidth: 0.64,
                glamour: false
            )
        default:
            self.init(
                skin: Color(red: 0.72, green: 0.49, blue: 0.34),
                upper: Color(red: 0.10, green: 0.12, blue: 0.15),
                lower: Color(red: 0.035, green: 0.040, blue: 0.052),
                accent: Color.watchfighterGold,
                hair: Color(red: 0.035, green: 0.025, blue: 0.020),
                boot: Color(red: 0.025, green: 0.025, blue: 0.030),
                scale: 1.0,
                armWidth: 0.28,
                legWidth: 0.35,
                glamour: false
            )
        }
    }

    private init(
        skin: Color,
        upper: Color,
        lower: Color,
        accent: Color,
        hair: Color,
        boot: Color,
        scale: CGFloat,
        armWidth: CGFloat,
        legWidth: CGFloat,
        glamour: Bool
    ) {
        self.skin = skin
        self.upper = upper
        self.lower = lower
        self.accent = accent
        self.hair = hair
        self.boot = boot
        self.scale = scale
        self.armWidth = armWidth
        self.legWidth = legWidth
        self.glamour = glamour
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
