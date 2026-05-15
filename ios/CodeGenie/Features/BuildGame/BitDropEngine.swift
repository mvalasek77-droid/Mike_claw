import SwiftUI
import Combine

/// BitDrop — CodeGenie's twist on Tetris. Pieces are shaped like Swift
/// syntax glyphs (curly braces, parens, arrow, dot, semicolon). When the
/// player clears a row, the build job they're watching gets a 2% speed
/// boost — a small, fair reward that doesn't gate progress.
@MainActor
final class BitDropGame: ObservableObject {
    static let cols = 8
    static let rows = 14

    /// One symbol on the board. Empty cells are nil.
    struct Cell: Hashable {
        let glyph: Glyph
        let hue: Double
    }

    enum Glyph: String, CaseIterable, Hashable {
        case openBrace  = "{"
        case closeBrace = "}"
        case openParen  = "("
        case closeParen = ")"
        case arrow      = "→"
        case dot        = "•"
        case semi       = ";"
        case star       = "✻"
    }

    /// Shape descriptor: piece is a list of (col, row) offsets relative to its origin.
    struct Piece: Hashable {
        var origin: (col: Int, row: Int)
        var offsets: [(Int, Int)]
        var glyph: Glyph
        var hue: Double

        func absoluteCells() -> [(Int, Int)] {
            offsets.map { (origin.col + $0.0, origin.row + $0.1) }
        }
        func rotated() -> Piece {
            var copy = self
            copy.offsets = offsets.map { (-$0.1, $0.0) }
            return copy
        }
        func moved(dc: Int, dr: Int) -> Piece {
            var copy = self
            copy.origin = (origin.col + dc, origin.row + dr)
            return copy
        }

        // Equatable manual — tuples aren't Equatable by default.
        static func == (lhs: Piece, rhs: Piece) -> Bool {
            lhs.origin == rhs.origin && lhs.glyph == rhs.glyph && lhs.hue == rhs.hue &&
            lhs.offsets.elementsEqual(rhs.offsets, by: ==)
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(origin.col); hasher.combine(origin.row)
            hasher.combine(glyph); hasher.combine(hue)
        }
    }

    @Published private(set) var board: [[Cell?]] = Array(
        repeating: Array(repeating: nil, count: cols), count: rows
    )
    @Published private(set) var current: Piece?
    @Published private(set) var next: Piece
    @Published private(set) var score: Int = 0
    @Published private(set) var rowsCleared: Int = 0
    @Published private(set) var isOver: Bool = false
    @Published private(set) var isPaused: Bool = false

    /// Build-speed boost the player has earned (0…1).
    var buildBoost: Double { min(0.5, Double(rowsCleared) * 0.02) }

    private var tickTask: Task<Void, Never>?
    private var tickInterval: UInt64 { UInt64(max(0.18, 0.6 - Double(rowsCleared) * 0.02) * 1_000_000_000) }

    init() {
        next = BitDropGame.spawn()
        spawnNew()
    }

    // MARK: Lifecycle

    func start() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                if !self.isPaused && !self.isOver { self.tick() }
                try? await Task.sleep(nanoseconds: self.tickInterval)
            }
        }
    }

    func stop() {
        tickTask?.cancel(); tickTask = nil
    }

    func togglePause() { isPaused.toggle(); Haptics.selection() }

    func reset() {
        board = Array(repeating: Array(repeating: nil, count: Self.cols), count: Self.rows)
        score = 0; rowsCleared = 0; isOver = false; isPaused = false
        next = Self.spawn()
        spawnNew()
    }

    // MARK: Movement

    func moveLeft()  { tryMove(dc: -1, dr: 0) }
    func moveRight() { tryMove(dc: 1, dr: 0) }
    func softDrop()  { tryMove(dc: 0, dr: 1) }

    func hardDrop() {
        guard var p = current else { return }
        while canPlace(p.moved(dc: 0, dr: 1)) { p = p.moved(dc: 0, dr: 1) }
        current = p
        Haptics.tap(intensity: 0.85, sharpness: 0.7)
        lockPiece()
    }

    func rotate() {
        guard let p = current else { return }
        let r = p.rotated()
        if canPlace(r) { current = r; Haptics.selection() }
    }

    // MARK: Tick

    private func tick() {
        if !tryMove(dc: 0, dr: 1) {
            lockPiece()
        }
    }

    @discardableResult
    private func tryMove(dc: Int, dr: Int) -> Bool {
        guard let p = current else { return false }
        let moved = p.moved(dc: dc, dr: dr)
        if canPlace(moved) {
            current = moved
            return true
        }
        return false
    }

    private func canPlace(_ piece: Piece) -> Bool {
        for (c, r) in piece.absoluteCells() {
            if c < 0 || c >= Self.cols || r >= Self.rows { return false }
            if r >= 0 && board[r][c] != nil { return false }
        }
        return true
    }

    private func lockPiece() {
        guard let p = current else { return }
        for (c, r) in p.absoluteCells() where r >= 0 {
            board[r][c] = Cell(glyph: p.glyph, hue: p.hue)
        }
        current = nil
        score += 10
        clearFullRows()
        spawnNew()
    }

    private func clearFullRows() {
        var newBoard = board
        var cleared = 0
        for r in (0..<Self.rows).reversed() {
            if newBoard[r].allSatisfy({ $0 != nil }) {
                newBoard.remove(at: r)
                newBoard.insert(Array(repeating: nil, count: Self.cols), at: 0)
                cleared += 1
            }
        }
        if cleared > 0 {
            board = newBoard
            rowsCleared += cleared
            score += cleared * cleared * 100
            Haptics.shimmer()
        }
    }

    private func spawnNew() {
        let piece = next
        next = Self.spawn()
        if !canPlace(piece) {
            isOver = true
            Haptics.error()
            return
        }
        current = piece
    }

    // MARK: Piece library

    private static let shapes: [[(Int, Int)]] = [
        // I
        [(0, 0), (1, 0), (2, 0), (3, 0)],
        // O
        [(0, 0), (1, 0), (0, 1), (1, 1)],
        // T
        [(0, 0), (1, 0), (2, 0), (1, 1)],
        // L
        [(0, 0), (0, 1), (0, 2), (1, 2)],
        // J
        [(1, 0), (1, 1), (1, 2), (0, 2)],
        // S
        [(1, 0), (2, 0), (0, 1), (1, 1)],
        // Z
        [(0, 0), (1, 0), (1, 1), (2, 1)]
    ]

    private static func spawn() -> Piece {
        let offs = shapes.randomElement()!
        let glyph = Glyph.allCases.randomElement()!
        let hue = Double.random(in: 0...1)
        let startCol = max(0, (cols / 2) - 1)
        return Piece(origin: (col: startCol, row: 0), offsets: offs, glyph: glyph, hue: hue)
    }
}
