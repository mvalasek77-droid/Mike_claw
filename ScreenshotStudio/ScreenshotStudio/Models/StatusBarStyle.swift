import SwiftUI

/// How a device class draws its status bar. Derived purely from the catalog
/// slot, so it's trivial to unit-test.
enum StatusBarLayoutKind: String, Codable, Hashable {
    case dynamicIsland   // 6.9" / 6.7" — time left, status right, Island pill
    case notch           // 6.5"        — time left, status right, no Island
    case classic         // 5.5"        — centered time, signal left, battery right
    case pad             // iPad        — centered, roomy

    var hasIsland: Bool { self == .dynamicIsland }
    var isModern: Bool { self == .dynamicIsland || self == .notch }
}

extension ASCDeviceSize {
    /// The status-bar layout this slot should render.
    var statusBarLayout: StatusBarLayoutKind {
        switch family {
        case .iPad: return .pad
        case .iPhone:
            if displayInches >= 6.7 { return .dynamicIsland }
            if displayInches >= 6.0 { return .notch }
            return .classic
        }
    }
}

/// A clean, synthetic status bar drawn over the top of the screenshot — the
/// App-Store convention (9:41, full battery, full signal + Wi-Fi). We overlay
/// rather than erase the real bar: reliable and pixel-predictable.
struct StatusBarStyle: Codable, Hashable {
    var enabled: Bool = true
    var time: String = "9:41"
    var batteryPercent: Int = 100
    var showBatteryPercent: Bool = false
    var carrier: String = "Carrier"
    var showCarrier: Bool = false
    var showCellular: Bool = true
    var showWiFi: Bool = true

    enum GlyphAppearance: String, Codable, CaseIterable, Identifiable, Hashable {
        case light, dark
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var color: Color { self == .light ? .white : Color(white: 0.08) }
    }
    var appearance: GlyphAppearance = .light
}

/// Lightweight, GPU-cheap image adjustments that "make screenshots pop". These
/// map directly onto SwiftUI's color filters, so they render identically in the
/// live preview and the off-screen exporter — no Core Image, no dual path.
struct ImageAdjustments: Codable, Hashable {
    var brightness: Double = 0   // -0.25 … 0.25
    var contrast: Double = 1     //  0.6  … 1.5
    var saturation: Double = 1   //  0    … 2
    var warmth: Double = 0       // -1 (cool) … 1 (warm)

    var clampedBrightness: Double { min(max(brightness, -0.25), 0.25) }
    var clampedContrast: Double { min(max(contrast, 0.6), 1.5) }
    var clampedSaturation: Double { min(max(saturation, 0), 2) }
    var clampedWarmth: Double { min(max(warmth, -1), 1) }

    /// Whether any adjustment deviates from neutral (used to skip work).
    var isNeutral: Bool {
        clampedBrightness == 0 && clampedContrast == 1 &&
        clampedSaturation == 1 && clampedWarmth == 0
    }

    /// A near-white tint for `.colorMultiply`: warm pushes toward amber, cool
    /// toward blue, and 0 is pure white (a no-op multiply).
    var warmthTint: Color {
        let w = clampedWarmth
        let warm = (r: 1.0, g: 0.93, b: 0.84)
        let cool = (r: 0.86, g: 0.93, b: 1.0)
        let white = (r: 1.0, g: 1.0, b: 1.0)
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        let target = w >= 0 ? warm : cool
        let t = abs(w) * 0.6 // keep the effect subtle
        return Color(.sRGB,
                     red: lerp(white.r, target.r, t),
                     green: lerp(white.g, target.g, t),
                     blue: lerp(white.b, target.b, t))
    }
}

/// One-tap enhancement presets.
struct EnhancePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let adjustments: ImageAdjustments

    static let all: [EnhancePreset] = [
        .init(id: "original", name: "Original", symbol: "circle.dashed",
              adjustments: ImageAdjustments()),
        .init(id: "pop", name: "Pop", symbol: "sparkles",
              adjustments: ImageAdjustments(brightness: 0.02, contrast: 1.12, saturation: 1.25, warmth: 0)),
        .init(id: "vivid", name: "Vivid", symbol: "wand.and.rays",
              adjustments: ImageAdjustments(brightness: 0.02, contrast: 1.18, saturation: 1.45, warmth: 0.1)),
        .init(id: "punch", name: "Punch", symbol: "bolt.fill",
              adjustments: ImageAdjustments(brightness: -0.02, contrast: 1.28, saturation: 1.22, warmth: 0)),
        .init(id: "warm", name: "Warm", symbol: "sun.max.fill",
              adjustments: ImageAdjustments(brightness: 0.02, contrast: 1.08, saturation: 1.12, warmth: 0.6)),
        .init(id: "cool", name: "Cool", symbol: "snowflake",
              adjustments: ImageAdjustments(brightness: 0.0, contrast: 1.08, saturation: 1.1, warmth: -0.6)),
        .init(id: "noir", name: "Noir", symbol: "moon.stars.fill",
              adjustments: ImageAdjustments(brightness: 0.0, contrast: 1.2, saturation: 0, warmth: 0))
    ]
}
