import Foundation

/// A free-floating text annotation or sticker placed over the composition.
///
/// Position and size are stored as fractions of the canvas, so an overlay
/// lands in exactly the same place at every export resolution — the same
/// WYSIWYG guarantee the rest of the studio makes.
struct CanvasOverlay: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, Hashable { case text, sticker }

    var id: UUID = UUID()
    var kind: Kind = .text
    /// Text content, or — for a `.sticker` — an emoji or SF Symbol name.
    var content: String = "New"
    /// When `kind == .sticker`, treat `content` as an SF Symbol name rather
    /// than literal glyphs (lets us mix emoji and symbol stickers).
    var isSymbol: Bool = false
    /// Center position as a fraction of the canvas (0…1, top-left origin).
    var x: Double = 0.5
    var y: Double = 0.5
    /// Size as a fraction of canvas width.
    var sizeFraction: Double = 0.1
    /// Rotation in degrees.
    var rotation: Double = 0
    var color: RGBAColor = .white
    var weight: CaptionStyle.FontWeightToken = .bold

    static func text(_ s: String = "New") -> CanvasOverlay {
        CanvasOverlay(kind: .text, content: s, isSymbol: false, sizeFraction: 0.075)
    }

    static func sticker(_ s: String, isSymbol: Bool) -> CanvasOverlay {
        CanvasOverlay(kind: .sticker, content: s, isSymbol: isSymbol, sizeFraction: 0.16)
    }
}

extension CanvasOverlay {
    /// A small palette of ready-to-drop sticker glyphs — a mix of emoji and SF
    /// Symbols so users can grab either without leaving the panel.
    static let stickerPalette: [(glyph: String, isSymbol: Bool)] = [
        ("✨", false), ("🔥", false), ("⭐️", false), ("❤️", false),
        ("👍", false), ("🎉", false), ("🚀", false), ("💡", false),
        ("star.fill", true), ("bolt.fill", true), ("heart.fill", true),
        ("checkmark.seal.fill", true), ("crown.fill", true), ("flame.fill", true),
        ("hand.thumbsup.fill", true), ("sparkles", true),
        ("arrow.right.circle.fill", true), ("bell.badge.fill", true)
    ]

    /// Quick text-badge presets.
    static let textPresets: [String] = ["NEW", "FREE", "PRO", "SALE", "Tap here", "Swipe →"]
}
