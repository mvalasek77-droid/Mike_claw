import Foundation

/// A single imported screenshot plus the per-slide overrides applied to it.
struct Slide: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// File name (not full path) of the source image inside the project folder.
    var imageFile: String
    /// Per-slide caption text for the primary language. When `nil`, the
    /// project's shared caption text is used — handy for batches that share
    /// one headline.
    var captionOverride: String? = nil
    /// Per-slide caption overrides for non-primary languages, keyed by App
    /// Store language code.
    var localizedOverrides: [String: String] = [:]
    /// Pixel size of the imported source image, captured at import time so we
    /// can compute layouts without decoding the image.
    var sourcePixelWidth: Double = 0
    var sourcePixelHeight: Double = 0

    var sourceSize: CGSize { CGSize(width: sourcePixelWidth, height: sourcePixelHeight) }

    enum CodingKeys: String, CodingKey {
        case id, imageFile, captionOverride, localizedOverrides, sourcePixelWidth, sourcePixelHeight
    }
}

extension Slide {
    /// Tolerant decoding so documents written before a field existed still
    /// load — synthesized `Decodable` ignores property defaults, which would
    /// otherwise throw on a missing key and lose the user's saved sets.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        imageFile = try c.decode(String.self, forKey: .imageFile)
        captionOverride = try c.decodeIfPresent(String.self, forKey: .captionOverride)
        localizedOverrides = try c.decodeIfPresent([String: String].self, forKey: .localizedOverrides) ?? [:]
        sourcePixelWidth = try c.decodeIfPresent(Double.self, forKey: .sourcePixelWidth) ?? 0
        sourcePixelHeight = try c.decodeIfPresent(Double.self, forKey: .sourcePixelHeight) ?? 0
    }
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

    /// App Store languages this set manages captions for. The first entry is
    /// the primary language (whose text lives in the legacy caption fields).
    var languages: [String] = [ASCLanguage.base]
    /// The language currently being edited / previewed in the studio.
    var activeLanguage: String = ASCLanguage.base

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

    /// The primary (first) language — its captions use the legacy fields.
    var primaryLanguage: String { languages.first ?? ASCLanguage.base }

    /// Resolved caption text for a slide in the currently active language.
    func captionText(for slide: Slide) -> String {
        captionText(for: slide, language: activeLanguage)
    }

    /// Resolved caption text for a slide in a specific language. Resolution
    /// order: per-slide override (for that language) → that language's shared
    /// headline → the primary language's text as a final fallback.
    func captionText(for slide: Slide, language: String) -> String {
        if language == primaryLanguage {
            if let override = slide.captionOverride, !override.isEmpty { return override }
            return style.caption.text
        }
        if let override = slide.localizedOverrides[language], !override.isEmpty { return override }
        if let headline = style.caption.localized[language], !headline.isEmpty { return headline }
        // Fall back to the primary language so a partially-localized set still
        // renders legible text everywhere.
        if let override = slide.captionOverride, !override.isEmpty { return override }
        return style.caption.text
    }

    static func newProject(name: String = "Untitled Set") -> ScreenshotProject {
        ScreenshotProject(name: name)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, modifiedAt, style, orientation
        case deviceSizeID, additionalSizeIDs, languages, activeLanguage, slides
    }
}

extension ScreenshotProject {
    /// Tolerant decoding (see `Slide.init(from:)`): new fields fall back to
    /// their defaults so older `projects.json` documents keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
        style = try c.decodeIfPresent(CanvasStyle.self, forKey: .style) ?? CanvasStyle()
        orientation = try c.decodeIfPresent(CanvasOrientation.self, forKey: .orientation) ?? .portrait
        deviceSizeID = try c.decodeIfPresent(String.self, forKey: .deviceSizeID) ?? ASCDeviceSize.default.id
        additionalSizeIDs = try c.decodeIfPresent([String].self, forKey: .additionalSizeIDs) ?? []
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? [ASCLanguage.base]
        activeLanguage = try c.decodeIfPresent(String.self, forKey: .activeLanguage) ?? ASCLanguage.base
        slides = try c.decodeIfPresent([Slide].self, forKey: .slides) ?? []
    }
}
