import SwiftUI

/// A `Codable`, `Color`-bridgeable RGBA value so styles can be persisted to
/// disk without dragging UIKit/SwiftUI types into our model layer.
struct RGBAColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    static func gray(_ v: Double, _ a: Double = 1) -> RGBAColor { .init(red: v, green: v, blue: v, alpha: a) }
    static let white = RGBAColor.gray(1)
    static let black = RGBAColor.gray(0)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    /// 0xRRGGBB convenience.
    init(hex: UInt32, alpha: Double = 1) {
        self.red   = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8)  & 0xFF) / 255
        self.blue  = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    /// Relative luminance (WCAG) — used to auto-pick legible caption colors.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }
}

/// The background painted behind the device / screenshot.
struct BackgroundStyle: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, Hashable { case solid, gradient }

    let id: String
    var name: String
    var kind: Kind
    /// One color for `.solid`; two-or-more stops for `.gradient`.
    var colors: [RGBAColor]
    /// Gradient angle in degrees (0 = left→right, 90 = top→bottom).
    var angle: Double = 135

    /// SwiftUI shape style ready to drop into `.background()` / `.fill()`.
    var shapeStyle: AnyShapeStyle {
        switch kind {
        case .solid:
            return AnyShapeStyle(colors.first?.color ?? Color.black)
        case .gradient:
            let stops = colors.isEmpty ? [RGBAColor.black] : colors
            let radians = Angle(degrees: angle).radians
            let unit = UnitPoint(x: 0.5 + 0.5 * cos(radians), y: 0.5 + 0.5 * sin(radians))
            let start = UnitPoint(x: 1 - unit.x, y: 1 - unit.y)
            return AnyShapeStyle(
                LinearGradient(colors: stops.map(\.color), startPoint: start, endPoint: unit)
            )
        }
    }

    /// Average luminance — drives automatic caption contrast.
    var averageLuminance: Double {
        guard !colors.isEmpty else { return 0 }
        return colors.map(\.luminance).reduce(0, +) / Double(colors.count)
    }
}

extension BackgroundStyle {
    /// Curated, App-Store-tasteful background presets.
    static let presets: [BackgroundStyle] = [
        .init(id: "midnight", name: "Midnight", kind: .gradient,
              colors: [RGBAColor(hex: 0x1B2A4A), RGBAColor(hex: 0x0B1020)], angle: 135),
        .init(id: "aurora", name: "Aurora", kind: .gradient,
              colors: [RGBAColor(hex: 0x6157FF), RGBAColor(hex: 0xEE49FD)], angle: 135),
        .init(id: "sunset", name: "Sunset", kind: .gradient,
              colors: [RGBAColor(hex: 0xFF6A88), RGBAColor(hex: 0xFF99AC), RGBAColor(hex: 0xFFC371)], angle: 120),
        .init(id: "mint", name: "Mint", kind: .gradient,
              colors: [RGBAColor(hex: 0x11998E), RGBAColor(hex: 0x38EF7D)], angle: 135),
        .init(id: "ocean", name: "Ocean", kind: .gradient,
              colors: [RGBAColor(hex: 0x2193B0), RGBAColor(hex: 0x6DD5ED)], angle: 135),
        .init(id: "graphite", name: "Graphite", kind: .gradient,
              colors: [RGBAColor(hex: 0x434343), RGBAColor(hex: 0x000000)], angle: 135),
        .init(id: "paper", name: "Paper", kind: .solid,
              colors: [RGBAColor(hex: 0xF5F5F7)]),
        .init(id: "snow", name: "Snow", kind: .solid,
              colors: [RGBAColor.white]),
        .init(id: "ink", name: "Ink", kind: .solid,
              colors: [RGBAColor(hex: 0x0B0B0F)]),
        .init(id: "coral", name: "Coral", kind: .gradient,
              colors: [RGBAColor(hex: 0xFF512F), RGBAColor(hex: 0xDD2476)], angle: 135)
    ]

    static var `default`: BackgroundStyle { presets[1] } // Aurora
}

/// Where the marketing caption sits relative to the device.
enum CaptionPlacement: String, Codable, CaseIterable, Identifiable, Hashable {
    case top, bottom, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .none: return "Hidden"
        }
    }
}

/// The headline drawn above or below the framed device.
struct CaptionStyle: Codable, Hashable {
    var text: String = "Your headline here"
    var placement: CaptionPlacement = .top
    /// Caption height as a fraction of the canvas height (0…0.45).
    var heightFraction: Double = 0.18
    /// Font size as a fraction of canvas width — keeps text scale identical
    /// across every device resolution.
    var sizeFraction: Double = 0.072
    var weight: FontWeightToken = .bold
    /// `nil` means "auto contrast against the background".
    var customColor: RGBAColor? = nil
    /// Per-language headline overrides, keyed by App Store language code. The
    /// primary language always lives in `text`; other locales live here so a
    /// single set can drive a fully localized App Store listing.
    var localized: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case text, placement, heightFraction, sizeFraction, weight, customColor, localized
    }

    enum FontWeightToken: String, Codable, CaseIterable, Identifiable, Hashable {
        case regular, medium, semibold, bold, heavy
        var id: String { rawValue }
        var swiftUIWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            }
        }
        var label: String { rawValue.capitalized }
    }
}

/// The complete, persistable description of how a screenshot is composed.
struct CanvasStyle: Codable, Hashable {
    var background: BackgroundStyle = .default
    var caption: CaptionStyle = CaptionStyle()
    /// Draw the screenshot inside a device bezel.
    var deviceFramed: Bool = true
    /// Margin around the device as a fraction of canvas width (0…0.35).
    var marginFraction: Double = 0.12
    /// Corner radius of the screenshot opening as a fraction of canvas width.
    var cornerFraction: Double = 0.052
    /// Drop shadow under the device.
    var shadow: Bool = true
    /// Clean, synthetic status bar drawn over the screenshot.
    var statusBar: StatusBarStyle = StatusBarStyle()
    /// Color adjustments applied to the source screenshot.
    var adjustments: ImageAdjustments = ImageAdjustments()
    /// Free-floating text annotations and stickers placed over the canvas.
    var overlays: [CanvasOverlay] = []

    enum CodingKeys: String, CodingKey {
        case background, caption, deviceFramed, marginFraction
        case cornerFraction, shadow, statusBar, adjustments, overlays
    }
}

extension CaptionStyle {
    /// Tolerant decoding so pre-localization documents still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? "Your headline here"
        placement = try c.decodeIfPresent(CaptionPlacement.self, forKey: .placement) ?? .top
        heightFraction = try c.decodeIfPresent(Double.self, forKey: .heightFraction) ?? 0.18
        sizeFraction = try c.decodeIfPresent(Double.self, forKey: .sizeFraction) ?? 0.072
        weight = try c.decodeIfPresent(FontWeightToken.self, forKey: .weight) ?? .bold
        customColor = try c.decodeIfPresent(RGBAColor.self, forKey: .customColor)
        localized = try c.decodeIfPresent([String: String].self, forKey: .localized) ?? [:]
    }
}

extension CanvasStyle {
    /// Tolerant decoding so documents written before overlays existed load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decodeIfPresent(BackgroundStyle.self, forKey: .background) ?? .default
        caption = try c.decodeIfPresent(CaptionStyle.self, forKey: .caption) ?? CaptionStyle()
        deviceFramed = try c.decodeIfPresent(Bool.self, forKey: .deviceFramed) ?? true
        marginFraction = try c.decodeIfPresent(Double.self, forKey: .marginFraction) ?? 0.12
        cornerFraction = try c.decodeIfPresent(Double.self, forKey: .cornerFraction) ?? 0.052
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? true
        statusBar = try c.decodeIfPresent(StatusBarStyle.self, forKey: .statusBar) ?? StatusBarStyle()
        adjustments = try c.decodeIfPresent(ImageAdjustments.self, forKey: .adjustments) ?? ImageAdjustments()
        overlays = try c.decodeIfPresent([CanvasOverlay].self, forKey: .overlays) ?? []
    }
}
