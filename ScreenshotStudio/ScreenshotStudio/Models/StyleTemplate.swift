import Foundation

/// A one-tap professional look — a complete `CanvasStyle` the user can apply to
/// any set and then fine-tune. Applying a template *restyles* a set: it keeps
/// the user's words (caption text + localizations), their status-bar settings,
/// and any overlays, swapping only the visual treatment.
struct StyleTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let style: CanvasStyle

    /// Look a curated background up by id, falling back to the default.
    private static func bg(_ id: String) -> BackgroundStyle {
        BackgroundStyle.presets.first { $0.id == id } ?? .default
    }

    /// Build a style from the handful of fields a template actually varies.
    private static func make(background: String,
                             placement: CaptionPlacement,
                             size: Double,
                             weight: CaptionStyle.FontWeightToken,
                             captionColor: RGBAColor? = nil,
                             margin: Double = 0.12,
                             corner: Double = 0.052,
                             framed: Bool = true,
                             shadow: Bool = true,
                             adjustments: ImageAdjustments = ImageAdjustments()) -> CanvasStyle {
        var s = CanvasStyle()
        s.background = bg(background)
        s.caption.placement = placement
        s.caption.sizeFraction = size
        s.caption.weight = weight
        s.caption.customColor = captionColor
        s.marginFraction = margin
        s.cornerFraction = corner
        s.deviceFramed = framed
        s.shadow = shadow
        s.adjustments = adjustments
        return s
    }
}

extension StyleTemplate {
    static let all: [StyleTemplate] = [
        StyleTemplate(id: "bold", name: "Bold",
            style: make(background: "aurora", placement: .top, size: 0.085, weight: .heavy,
                        margin: 0.12,
                        adjustments: ImageAdjustments(brightness: 0.02, contrast: 1.12, saturation: 1.25, warmth: 0))),

        StyleTemplate(id: "minimal", name: "Minimal",
            style: make(background: "paper", placement: .top, size: 0.06, weight: .semibold,
                        captionColor: .gray(0.07), margin: 0.16, shadow: false)),

        StyleTemplate(id: "playful", name: "Playful",
            style: make(background: "sunset", placement: .bottom, size: 0.078, weight: .bold,
                        margin: 0.1,
                        adjustments: ImageAdjustments(brightness: 0.02, contrast: 1.18, saturation: 1.45, warmth: 0.1))),

        StyleTemplate(id: "editorial", name: "Editorial",
            style: make(background: "ink", placement: .top, size: 0.07, weight: .bold,
                        captionColor: .white, margin: 0.14)),

        StyleTemplate(id: "frameless", name: "Frameless",
            style: make(background: "midnight", placement: .top, size: 0.066, weight: .semibold,
                        margin: 0.06, framed: false,
                        adjustments: ImageAdjustments(brightness: 0.02, contrast: 1.12, saturation: 1.25, warmth: 0))),

        StyleTemplate(id: "midnight-pro", name: "Midnight Pro",
            style: make(background: "midnight", placement: .bottom, size: 0.075, weight: .heavy,
                        margin: 0.12,
                        adjustments: ImageAdjustments(brightness: -0.02, contrast: 1.28, saturation: 1.22, warmth: 0))),

        StyleTemplate(id: "sunset-social", name: "Sunset",
            style: make(background: "coral", placement: .top, size: 0.08, weight: .bold,
                        margin: 0.1,
                        adjustments: ImageAdjustments(brightness: 0.02, contrast: 1.08, saturation: 1.12, warmth: 0.6))),

        StyleTemplate(id: "clean-light", name: "Clean",
            style: make(background: "snow", placement: .top, size: 0.07, weight: .bold,
                        captionColor: .gray(0.07), margin: 0.15))
    ]
}
