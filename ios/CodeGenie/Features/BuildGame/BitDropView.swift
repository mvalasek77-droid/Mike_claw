import SwiftUI

struct BitDropView: View {
    @ObservedObject var game: BitDropGame
    @State private var lastDragX: CGFloat = 0
    @State private var hasMovedThisDrag: Bool = false

    private let cellSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                board
                sidebar
            }
            controls
        }
        .onAppear { game.start() }
        .onDisappear { game.stop() }
    }

    // MARK: Sub-views

    private var board: some View {
        ZStack {
            // Background grid
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )

            VStack(spacing: 1) {
                ForEach(0..<BitDropGame.rows, id: \.self) { r in
                    HStack(spacing: 1) {
                        ForEach(0..<BitDropGame.cols, id: \.self) { c in
                            cellView(row: r, col: c)
                        }
                    }
                }
            }
            .padding(4)
        }
        .frame(
            width: CGFloat(BitDropGame.cols) * cellSize + 8,
            height: CGFloat(BitDropGame.rows) * cellSize + 8
        )
        .gesture(boardDragGesture)
        .onTapGesture(count: 2) { game.hardDrop() }
        .onTapGesture { game.rotate() }
        .overlay {
            if game.isOver { gameOver }
            else if game.isPaused { paused }
        }
    }

    private func cellView(row: Int, col: Int) -> some View {
        let placed = game.board[row][col]
        let active = game.current?.absoluteCells().contains(where: { $0.0 == col && $0.1 == row }) ?? false
        let glyph: BitDropGame.Glyph? = placed?.glyph ?? (active ? game.current?.glyph : nil)
        let hue = placed?.hue ?? (active ? game.current?.hue ?? 0 : 0)

        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(glyph == nil ? Color.white.opacity(0.04)
                      : Color(hue: hue, saturation: 0.65, brightness: 0.95).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.white.opacity(glyph == nil ? 0.05 : 0.4), lineWidth: 0.6)
                )
            if let g = glyph {
                Text(g.rawValue)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(LiquidGlass.primaryText)
            }
        }
        .frame(width: cellSize - 1, height: cellSize - 1)
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("SCORE").font(.caption2).foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                Text("\(game.score)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(LiquidGlass.primaryText)
                    .contentTransition(.numericText())
            }
            VStack(spacing: 4) {
                Text("LINES").font(.caption2).foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                Text("\(game.rowsCleared)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(LiquidGlass.primaryText)
            }
            VStack(spacing: 4) {
                Text("BOOST").font(.caption2).foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                Text("+\(Int(game.buildBoost * 100))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.success)
            }
            VStack(spacing: 4) {
                Text("NEXT").font(.caption2).foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                nextPiecePreview
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .frame(width: 80)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1)))
    }

    private var nextPiecePreview: some View {
        let piece = game.next
        let cols = (piece.offsets.map { $0.0 }.max() ?? 0) + 1
        let rows = (piece.offsets.map { $0.1 }.max() ?? 0) + 1
        return ZStack {
            VStack(spacing: 1) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 1) {
                        ForEach(0..<cols, id: \.self) { c in
                            let on = piece.offsets.contains(where: { $0.0 == c && $0.1 == r })
                            ZStack {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(on
                                          ? Color(hue: piece.hue, saturation: 0.65, brightness: 0.95).opacity(0.85)
                                          : Color.clear)
                                if on {
                                    Text(piece.glyph.rawValue)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(LiquidGlass.primaryText)
                                }
                            }
                            .frame(width: 12, height: 12)
                        }
                    }
                }
            }
        }
        .frame(height: 50)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            controlButton("arrow.left") { game.moveLeft() }
            controlButton("arrow.down") { game.softDrop() }
            controlButton("arrow.right") { game.moveRight() }
            Spacer()
            controlButton("arrow.clockwise") { game.rotate() }
            controlButton("arrow.down.to.line") { game.hardDrop() }
            controlButton(game.isPaused ? "play.fill" : "pause.fill") { game.togglePause() }
        }
    }

    private func controlButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(intensity: 0.4, sharpness: 0.6); action() }) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LiquidGlass.primaryText)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    private var boardDragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let dx = value.translation.width - lastDragX
                if abs(dx) > cellSize {
                    if dx > 0 { game.moveRight() } else { game.moveLeft() }
                    lastDragX = value.translation.width
                    hasMovedThisDrag = true
                }
                if value.translation.height > 60 && !hasMovedThisDrag {
                    game.softDrop()
                }
            }
            .onEnded { _ in
                lastDragX = 0
                hasMovedThisDrag = false
            }
    }

    private var gameOver: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 10) {
                Text("Game over")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("Score: \(game.score)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                PrimaryButton(title: "Play again", systemImage: "arrow.counterclockwise", style: .glass) {
                    game.reset()
                }
                .frame(maxWidth: 180)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var paused: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 8) {
                Image(systemName: "pause.circle.fill").font(.system(size: 40)).foregroundStyle(LiquidGlass.primaryText)
                Text("Paused")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
