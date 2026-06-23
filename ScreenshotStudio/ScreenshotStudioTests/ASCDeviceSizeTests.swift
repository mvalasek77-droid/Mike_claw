import XCTest
@testable import ScreenshotStudio

final class ASCDeviceSizeTests: XCTestCase {

    func testCatalogIsNonEmptyAndUniquelyIdentified() {
        XCTAssertFalse(ASCDeviceSize.catalog.isEmpty)
        let ids = ASCDeviceSize.catalog.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Device size IDs must be unique")
    }

    func testEveryCatalogEntryHasPositiveResolution() {
        for size in ASCDeviceSize.catalog {
            XCTAssertGreaterThan(size.portraitSize.width, 0, "\(size.id) width")
            XCTAssertGreaterThan(size.portraitSize.height, 0, "\(size.id) height")
            // App Store screenshots are taller than they are wide in portrait.
            XCTAssertGreaterThan(size.portraitSize.height, size.portraitSize.width, "\(size.id) should be portrait")
        }
    }

    func testKnownRequiredSizeDimensions() {
        // These are the exact pixel sizes App Store Connect validates.
        let sixNine = ASCDeviceSize.named("iphone-6_9")
        XCTAssertEqual(sixNine?.portraitSize, CGSize(width: 1320, height: 2868))

        let sixFive = ASCDeviceSize.named("iphone-6_5")
        XCTAssertEqual(sixFive?.portraitSize, CGSize(width: 1242, height: 2688))

        let iPad13 = ASCDeviceSize.named("ipad-13")
        XCTAssertEqual(iPad13?.portraitSize, CGSize(width: 2064, height: 2752))

        let iPad129 = ASCDeviceSize.named("ipad-12_9")
        XCTAssertEqual(iPad129?.portraitSize, CGSize(width: 2048, height: 2732))

        let sixSeven = ASCDeviceSize.named("iphone-6_7")
        XCTAssertEqual(sixSeven?.portraitSize, CGSize(width: 1290, height: 2796))
    }

    func testStatusBarLayoutPerDeviceClass() {
        XCTAssertEqual(ASCDeviceSize.named("iphone-6_9")?.statusBarLayout, .dynamicIsland)
        XCTAssertEqual(ASCDeviceSize.named("iphone-6_5")?.statusBarLayout, .notch)
        XCTAssertEqual(ASCDeviceSize.named("iphone-5_5")?.statusBarLayout, .classic)
        XCTAssertEqual(ASCDeviceSize.named("ipad-13")?.statusBarLayout, .pad)
        XCTAssertEqual(ASCDeviceSize.named("ipad-12_9")?.statusBarLayout, .pad)
    }

    func testLandscapeSwapsDimensions() {
        let size = ASCDeviceSize.default
        let portrait = size.pixelSize(for: .portrait)
        let landscape = size.pixelSize(for: .landscape)
        XCTAssertEqual(portrait.width, landscape.height)
        XCTAssertEqual(portrait.height, landscape.width)
    }

    func testRequiredSubsetMatchesFlag() {
        let required = ASCDeviceSize.required
        XCTAssertFalse(required.isEmpty)
        XCTAssertTrue(required.allSatisfy(\.isRequired))
    }

    func testResolutionLabelFormatting() {
        let size = ASCDeviceSize.named("iphone-6_9")!
        XCTAssertEqual(size.resolutionLabel(for: .portrait), "1320 × 2868 px")
        XCTAssertEqual(size.resolutionLabel(for: .landscape), "2868 × 1320 px")
    }

    func testNamedReturnsNilForUnknownID() {
        XCTAssertNil(ASCDeviceSize.named("does-not-exist"))
    }

    func testAspectRatioIsPositive() {
        for size in ASCDeviceSize.catalog {
            XCTAssertGreaterThan(size.aspectRatio(for: .portrait), 0)
            XCTAssertLessThan(size.aspectRatio(for: .portrait), 1, "portrait aspect < 1")
        }
    }
}
