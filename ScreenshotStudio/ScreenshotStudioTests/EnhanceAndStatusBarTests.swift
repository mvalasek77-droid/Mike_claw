import XCTest
import SwiftUI
@testable import ScreenshotStudio

final class EnhanceAndStatusBarTests: XCTestCase {

    // MARK: Status bar layout mapping

    func testStatusBarLayoutPerDeviceClass() {
        XCTAssertEqual(ASCDeviceSize.named("iphone-6_9")?.statusBarLayout, .dynamicIsland)
        XCTAssertEqual(ASCDeviceSize.named("iphone-6_7")?.statusBarLayout, .dynamicIsland)
        XCTAssertEqual(ASCDeviceSize.named("iphone-6_5")?.statusBarLayout, .notch)
        XCTAssertEqual(ASCDeviceSize.named("iphone-5_5")?.statusBarLayout, .classic)
        XCTAssertEqual(ASCDeviceSize.named("ipad-13")?.statusBarLayout, .pad)
        XCTAssertEqual(ASCDeviceSize.named("ipad-12_9")?.statusBarLayout, .pad)
    }

    func testEveryCatalogSlotHasALayout() {
        for size in ASCDeviceSize.catalog {
            // No crashes / all branches covered.
            let layout = size.statusBarLayout
            if size.family == .iPad {
                XCTAssertEqual(layout, .pad)
            } else {
                XCTAssertNotEqual(layout, .pad)
            }
        }
    }

    func testIslandImpliesModern() {
        XCTAssertTrue(StatusBarLayoutKind.dynamicIsland.isModern)
        XCTAssertTrue(StatusBarLayoutKind.dynamicIsland.hasIsland)
        XCTAssertTrue(StatusBarLayoutKind.notch.isModern)
        XCTAssertFalse(StatusBarLayoutKind.notch.hasIsland)
        XCTAssertFalse(StatusBarLayoutKind.classic.isModern)
        XCTAssertFalse(StatusBarLayoutKind.pad.isModern)
    }

    func testStatusBarStyleRoundTrips() throws {
        var style = StatusBarStyle()
        style.time = "10:30"
        style.batteryPercent = 42
        style.showBatteryPercent = true
        style.showCarrier = true
        style.carrier = "Studio"
        style.appearance = .dark

        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(StatusBarStyle.self, from: data)
        XCTAssertEqual(decoded, style)
    }

    // MARK: Image adjustments

    func testAdjustmentsClampOutOfRangeValues() {
        var adj = ImageAdjustments()
        adj.brightness = 5
        adj.contrast = -3
        adj.saturation = 99
        adj.warmth = 4
        XCTAssertEqual(adj.clampedBrightness, 0.25, accuracy: 0.0001)
        XCTAssertEqual(adj.clampedContrast, 0.6, accuracy: 0.0001)
        XCTAssertEqual(adj.clampedSaturation, 2, accuracy: 0.0001)
        XCTAssertEqual(adj.clampedWarmth, 1, accuracy: 0.0001)
    }

    func testDefaultAdjustmentsAreNeutral() {
        XCTAssertTrue(ImageAdjustments().isNeutral)
        XCTAssertFalse(ImageAdjustments(brightness: 0.1).isNeutral)
        XCTAssertFalse(ImageAdjustments(saturation: 1.4).isNeutral)
    }

    func testEnhancePresetsAreUniqueAndOriginalIsNeutral() {
        let ids = EnhancePreset.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "preset ids must be unique")

        let original = EnhancePreset.all.first { $0.id == "original" }
        XCTAssertNotNil(original)
        XCTAssertTrue(original!.adjustments.isNeutral)

        // "Pop" should actually do something.
        let pop = EnhancePreset.all.first { $0.id == "pop" }!
        XCTAssertFalse(pop.adjustments.isNeutral)
        XCTAssertGreaterThan(pop.adjustments.saturation, 1)
    }

    func testWarmthTintNeutralAtZero() {
        let adj = ImageAdjustments(warmth: 0)
        // At warmth 0 the multiply tint must be (near) pure white so that
        // `.colorMultiply(warmthTint)` is a genuine no-op.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(adj.warmthTint).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1, accuracy: 0.001)
        XCTAssertEqual(g, 1, accuracy: 0.001)
        XCTAssertEqual(b, 1, accuracy: 0.001)
    }
}
