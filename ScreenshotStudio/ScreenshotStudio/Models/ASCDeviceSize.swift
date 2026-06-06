import CoreGraphics
import Foundation

/// Orientation of an exported screenshot.
enum CanvasOrientation: String, Codable, CaseIterable, Identifiable, Hashable {
    case portrait
    case landscape
    var id: String { rawValue }

    var label: String { self == .portrait ? "Portrait" : "Landscape" }
    var symbol: String { self == .portrait ? "iphone" : "iphone.landscape" }
}

/// Device family an App Store Connect screenshot slot belongs to.
enum DeviceFamily: String, Codable, CaseIterable, Identifiable, Hashable {
    case iPhone
    case iPad
    var id: String { rawValue }

    var label: String { self == .iPhone ? "iPhone" : "iPad" }
    var symbol: String { self == .iPhone ? "iphone" : "ipad" }
}

/// An exact App Store Connect screenshot specification.
///
/// Dimensions are the **pixel** sizes Apple validates against at upload time.
/// `portraitSize` is the canonical portrait resolution; landscape simply
/// swaps width and height. Keeping this as plain data (no UIKit) makes the
/// whole catalog trivially unit-testable on any platform.
struct ASCDeviceSize: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let family: DeviceFamily
    /// Diagonal display size in inches, e.g. 6.9.
    let displayInches: Double
    /// Canonical portrait resolution in pixels.
    let portraitSize: CGSize
    /// Whether App Store Connect currently *requires* this slot for new
    /// submissions (versus accepting it as an optional/legacy size).
    let isRequired: Bool
    /// Representative devices, shown to the user for context.
    let exampleDevices: String

    /// Pixel size for a given orientation.
    func pixelSize(for orientation: CanvasOrientation) -> CGSize {
        switch orientation {
        case .portrait:  return portraitSize
        case .landscape: return CGSize(width: portraitSize.height, height: portraitSize.width)
        }
    }

    /// Aspect ratio (w/h) for a given orientation. Always > 0 for catalog data.
    func aspectRatio(for orientation: CanvasOrientation) -> CGFloat {
        let s = pixelSize(for: orientation)
        return s.height == 0 ? 1 : s.width / s.height
    }

    /// "1320 × 2868 px" style label for the given orientation.
    func resolutionLabel(for orientation: CanvasOrientation) -> String {
        let s = pixelSize(for: orientation)
        return "\(Int(s.width)) × \(Int(s.height)) px"
    }
}

extension ASCDeviceSize {
    /// The curated catalog of App Store Connect screenshot slots.
    ///
    /// Sources: App Store Connect "Screenshot specifications" reference. We
    /// expose the modern required sizes first, then widely-accepted legacy
    /// sizes so an indie dev can fill every slot their app still supports.
    static let catalog: [ASCDeviceSize] = [
        ASCDeviceSize(
            id: "iphone-6_9",
            displayName: "iPhone 6.9\"",
            family: .iPhone,
            displayInches: 6.9,
            portraitSize: CGSize(width: 1320, height: 2868),
            isRequired: true,
            exampleDevices: "iPhone 16 Pro Max · 16 Plus · 15 Pro Max"
        ),
        ASCDeviceSize(
            id: "iphone-6_7",
            displayName: "iPhone 6.7\"",
            family: .iPhone,
            displayInches: 6.7,
            portraitSize: CGSize(width: 1290, height: 2796),
            isRequired: false,
            exampleDevices: "iPhone 15 Pro Max · 14 Pro Max · 13 Pro Max"
        ),
        ASCDeviceSize(
            id: "iphone-6_5",
            displayName: "iPhone 6.5\"",
            family: .iPhone,
            displayInches: 6.5,
            portraitSize: CGSize(width: 1242, height: 2688),
            isRequired: true,
            exampleDevices: "iPhone 11 Pro Max · XS Max"
        ),
        ASCDeviceSize(
            id: "iphone-5_5",
            displayName: "iPhone 5.5\"",
            family: .iPhone,
            displayInches: 5.5,
            portraitSize: CGSize(width: 1242, height: 2208),
            isRequired: false,
            exampleDevices: "iPhone 8 Plus · 7 Plus · 6s Plus"
        ),
        ASCDeviceSize(
            id: "ipad-13",
            displayName: "iPad 13\"",
            family: .iPad,
            displayInches: 13.0,
            portraitSize: CGSize(width: 2064, height: 2752),
            isRequired: true,
            exampleDevices: "iPad Pro 13\" (M4)"
        ),
        ASCDeviceSize(
            id: "ipad-12_9",
            displayName: "iPad 12.9\"",
            family: .iPad,
            displayInches: 12.9,
            portraitSize: CGSize(width: 2048, height: 2732),
            isRequired: false,
            exampleDevices: "iPad Pro 12.9\" (2nd–6th gen)"
        )
    ]

    /// Look up a spec by its stable identifier.
    static func named(_ id: String) -> ASCDeviceSize? {
        catalog.first { $0.id == id }
    }

    /// The default slot a brand-new project targets.
    static var `default`: ASCDeviceSize { catalog[0] }

    /// Slots Apple requires for a complete submission.
    static var required: [ASCDeviceSize] { catalog.filter(\.isRequired) }
}
