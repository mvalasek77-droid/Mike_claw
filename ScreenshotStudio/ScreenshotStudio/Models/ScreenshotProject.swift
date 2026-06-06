import Foundation

/// A single imported screenshot plus the per-slide overrides applied to it.
struct Slide: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// File name (not full path) of the source image inside the project folder.
    var imageFile: String
    /// Per-slide caption text. When `nil`, the project's shared caption text
    /// is used — handy for batches that share one headline.
    var captionOverride: String? = nil
    /// Pixel size of the imported source image, captured at import time so we
    /// can compute layouts without decoding the image.
    var sourcePixelWidth: Double = 0
    var sourcePixelHeight: Double = 0

    var sourceSize: CGSize { CGSize(width: sourcePixelWidth, height: sourcePixelHeight) }
}

/// A marketing screenshot set: shared styling, a target device size, and an
/// ordered list of slides. This is the document the user creates and exports.
struct ScreenshotProject: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    var style: CanvasStyle = CanvasStyle()
    var orientation: CanvasOrientation = .portrait
    /// The App Store Connect slot this set targets.
    var deviceSizeID: String = ASCDeviceSize.default.id
    /// Additional slots to also render when exporting "all sizes".
    var additionalSizeIDs: [String] = []

    var slides: [Slide] = []

    var deviceSize: ASCDeviceSize {
        ASCDeviceSize.named(deviceSizeID) ?? .default
    }

    /// Every slot this project will export to (primary + extras), de-duped and
    /// preserving catalog order for a predictable export sequence.
    var exportSizes: [ASCDeviceSize] {
        let ids = Set([deviceSizeID] + additionalSizeIDs)
        return ASCDeviceSize.catalog.filter { ids.contains($0.id) }
    }

    /// Resolved caption text for a slide (override → shared → empty).
    func captionText(for slide: Slide) -> String {
        if let override = slide.captionOverride, !override.isEmpty { return override }
        return style.caption.text
    }

    static func newProject(name: String = "Untitled Set") -> ScreenshotProject {
        ScreenshotProject(name: name)
    }
}
