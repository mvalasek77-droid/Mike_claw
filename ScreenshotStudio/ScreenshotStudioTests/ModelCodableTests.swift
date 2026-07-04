import XCTest
@testable import ScreenshotStudio

final class ModelCodableTests: XCTestCase {

    func testProjectRoundTripsThroughJSON() throws {
        var project = ScreenshotProject.newProject(name: "Launch Set")
        project.style.background = BackgroundStyle.presets[2]
        project.style.caption.text = "Ship it"
        project.style.caption.placement = .bottom
        project.orientation = .landscape
        project.deviceSizeID = "iphone-6_5"
        project.additionalSizeIDs = ["ipad-13"]
        project.slides = [
            Slide(imageFile: "a.png", captionOverride: "First", sourcePixelWidth: 1179, sourcePixelHeight: 2556),
            Slide(imageFile: "b.png")
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(project)
        let decoded = try decoder.decode(ScreenshotProject.self, from: data)

        XCTAssertEqual(decoded.id, project.id)
        XCTAssertEqual(decoded.name, "Launch Set")
        XCTAssertEqual(decoded.orientation, .landscape)
        XCTAssertEqual(decoded.deviceSizeID, "iphone-6_5")
        XCTAssertEqual(decoded.additionalSizeIDs, ["ipad-13"])
        XCTAssertEqual(decoded.slides.count, 2)
        XCTAssertEqual(decoded.style.caption.placement, .bottom)
        XCTAssertEqual(decoded.style.background.id, BackgroundStyle.presets[2].id)
    }

    func testExportSizesDeduplicatesAndKeepsCatalogOrder() {
        var project = ScreenshotProject.newProject()
        project.deviceSizeID = "iphone-6_5"
        // Include a duplicate of the primary plus an out-of-order extra.
        project.additionalSizeIDs = ["ipad-13", "iphone-6_5", "iphone-6_9"]

        let ids = project.exportSizes.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "no duplicates")
        // Catalog order: 6.9 comes before 6.5 which comes before iPad 13.
        XCTAssertEqual(ids, ["iphone-6_9", "iphone-6_5", "ipad-13"])
    }

    func testCaptionTextPrefersSlideOverride() {
        var project = ScreenshotProject.newProject()
        project.style.caption.text = "Shared"
        let withOverride = Slide(imageFile: "x.png", captionOverride: "Specific")
        let withoutOverride = Slide(imageFile: "y.png")
        let blankOverride = Slide(imageFile: "z.png", captionOverride: "")

        XCTAssertEqual(project.captionText(for: withOverride), "Specific")
        XCTAssertEqual(project.captionText(for: withoutOverride), "Shared")
        XCTAssertEqual(project.captionText(for: blankOverride), "Shared")
    }

    func testProjectRoundTripsOverlaysAndLocalization() throws {
        var project = ScreenshotProject.newProject(name: "Localized")
        project.languages = ["en-US", "fr-FR", "ja"]
        project.activeLanguage = "fr-FR"
        project.style.caption.localized = ["fr-FR": "Bonjour", "ja": "こんにちは"]
        project.style.caption.design = .serif
        project.style.bezelTone = .white
        project.style.fullBleed = true
        project.style.background.imageDim = 0.4
        project.style.overlays = [
            CanvasOverlay.text("NEW"),
            CanvasOverlay.sticker("star.fill", isSymbol: true)
        ]
        project.slides = [
            Slide(imageFile: "a.png", captionOverride: "Base",
                  localizedOverrides: ["fr-FR": "Salut"])
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(project)
        let decoded = try decoder.decode(ScreenshotProject.self, from: data)

        XCTAssertEqual(decoded.languages, ["en-US", "fr-FR", "ja"])
        XCTAssertEqual(decoded.activeLanguage, "fr-FR")
        XCTAssertEqual(decoded.style.caption.localized["fr-FR"], "Bonjour")
        XCTAssertEqual(decoded.style.caption.design, .serif)
        XCTAssertEqual(decoded.style.bezelTone, .white)
        XCTAssertTrue(decoded.style.fullBleed)
        XCTAssertEqual(decoded.style.background.imageDim, 0.4, accuracy: 0.001)
        XCTAssertEqual(decoded.style.overlays.count, 2)
        XCTAssertEqual(decoded.style.overlays.first?.content, "NEW")
        XCTAssertEqual(decoded.slides.first?.localizedOverrides["fr-FR"], "Salut")
    }

    func testLegacyProjectDecodesWithLocalizationDefaults() throws {
        // A document encoded before localization/overlays existed must still
        // decode, picking up sensible defaults for the new fields.
        let legacy = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy",
          "createdAt": "2024-01-01T00:00:00Z",
          "modifiedAt": "2024-01-01T00:00:00Z",
          "orientation": "portrait",
          "deviceSizeID": "iphone-6_9",
          "additionalSizeIDs": [],
          "slides": [],
          "style": {
            "background": { "id": "aurora", "name": "Aurora", "kind": "gradient",
                            "colors": [], "angle": 135 },
            "caption": { "text": "Hi", "placement": "top", "heightFraction": 0.18,
                         "sizeFraction": 0.072, "weight": "bold" },
            "deviceFramed": true, "marginFraction": 0.12, "cornerFraction": 0.052,
            "shadow": true,
            "statusBar": { "enabled": true, "time": "9:41", "batteryPercent": 100,
                           "showBatteryPercent": false, "carrier": "Carrier",
                           "showCarrier": false, "showCellular": true,
                           "showWiFi": true, "appearance": "light" },
            "adjustments": { "brightness": 0, "contrast": 1, "saturation": 1, "warmth": 0 }
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(ScreenshotProject.self, from: legacy)

        XCTAssertEqual(project.languages, [ASCLanguage.base])
        XCTAssertEqual(project.activeLanguage, ASCLanguage.base)
        XCTAssertTrue(project.style.overlays.isEmpty)
        XCTAssertTrue(project.style.caption.localized.isEmpty)
    }

    func testCaptionResolutionAcrossLanguages() {
        var project = ScreenshotProject.newProject()
        project.languages = ["en-US", "fr-FR"]
        project.style.caption.text = "Hello"
        project.style.caption.localized = ["fr-FR": "Bonjour"]

        let plain = Slide(imageFile: "a.png")
        let baseOverride = Slide(imageFile: "b.png", captionOverride: "Base only")
        let frOverride = Slide(imageFile: "c.png", localizedOverrides: ["fr-FR": "Salut"])

        // Shared headline per language.
        XCTAssertEqual(project.captionText(for: plain, language: "en-US"), "Hello")
        XCTAssertEqual(project.captionText(for: plain, language: "fr-FR"), "Bonjour")

        // A base (English) per-slide override applies to the primary language,
        // but a localized shared headline wins for that language — you don't
        // want English text leaking into a French screenshot set.
        XCTAssertEqual(project.captionText(for: baseOverride, language: "en-US"), "Base only")
        XCTAssertEqual(project.captionText(for: baseOverride, language: "fr-FR"), "Bonjour")
        XCTAssertEqual(project.captionText(for: frOverride, language: "fr-FR"), "Salut")
        XCTAssertEqual(project.captionText(for: frOverride, language: "en-US"), "Hello")

        // A language with no localized headline falls back to the base text.
        XCTAssertEqual(project.captionText(for: plain, language: "ja"), "Hello")
    }

    @MainActor
    func testDuplicateCreatesIndependentlyNamedCopy() {
        let store = ProjectStore(loadFromDisk: false)
        let original = ScreenshotProject.newProject(name: "Launch")

        let dup = store.duplicate(original)
        XCTAssertNotEqual(dup.id, original.id)
        XCTAssertEqual(dup.name, "Launch copy")
        XCTAssertTrue(store.projects.contains { $0.id == dup.id })

        // A second duplicate avoids a name collision.
        let dup2 = store.duplicate(original)
        XCTAssertEqual(dup2.name, "Launch copy 2")
    }

    @MainActor
    func testOrphanCleanupRemovesOnlyOldUnreferencedFiles() throws {
        let fm = FileManager.default
        let dir = Workspace.imagesDirectory
        let referenced = "test-ref-\(UUID().uuidString).png"
        let orphanOld = "test-old-\(UUID().uuidString).png"
        let orphanFresh = "test-fresh-\(UUID().uuidString).png"
        let bytes = Data([0, 1, 2, 3])
        for name in [referenced, orphanOld, orphanFresh] {
            try bytes.write(to: dir.appendingPathComponent(name))
        }
        // Age the old orphan past the cleanup grace period.
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-600)],
                             ofItemAtPath: dir.appendingPathComponent(orphanOld).path)

        let store = ProjectStore(loadFromDisk: false)
        var project = ScreenshotProject.newProject(name: "Ref")
        project.slides = [Slide(imageFile: referenced)]
        store.upsert(project)

        let removed = store.cleanUpOrphanedImages()

        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent(referenced).path), "referenced file kept")
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent(orphanFresh).path), "fresh orphan kept (grace period)")
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent(orphanOld).path), "old orphan removed")
        XCTAssertGreaterThanOrEqual(removed, 1)

        // Cleanup anything this test left behind.
        for name in [referenced, orphanFresh] {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    func testRGBAColorHexInit() {
        let c = RGBAColor(hex: 0xFF8000)
        XCTAssertEqual(c.red, 1.0, accuracy: 0.001)
        XCTAssertEqual(c.green, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.blue, 0.0, accuracy: 0.001)
    }

    func testLuminanceOrdering() {
        XCTAssertGreaterThan(RGBAColor.white.luminance, RGBAColor.black.luminance)
        XCTAssertEqual(RGBAColor.white.luminance, 1.0, accuracy: 0.01)
        XCTAssertEqual(RGBAColor.black.luminance, 0.0, accuracy: 0.01)
    }

    func testBackgroundAverageLuminanceWithinBounds() {
        for preset in BackgroundStyle.presets {
            let l = preset.averageLuminance
            XCTAssertGreaterThanOrEqual(l, 0)
            XCTAssertLessThanOrEqual(l, 1)
        }
    }
}
