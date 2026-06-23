import XCTest
@testable import ScreenshotStudio

final class ScreenshotComposerTests: XCTestCase {

    private let canvas = CGSize(width: 1320, height: 2868) // iPhone 6.9"
    private let phoneSource = CGSize(width: 1179, height: 2556) // iPhone 15 raw shot

    // MARK: aspectFit

    func testAspectFitTallSourceIsHeightBound() {
        let container = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let fit = ScreenshotComposer.aspectFit(aspect: 0.5, in: container) // tall
        XCTAssertEqual(fit.height, 1000, accuracy: 1)
        XCTAssertEqual(fit.width, 500, accuracy: 1)
        // Centered horizontally.
        XCTAssertEqual(fit.midX, container.midX, accuracy: 1)
    }

    func testAspectFitWideSourceIsWidthBound() {
        let container = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let fit = ScreenshotComposer.aspectFit(aspect: 2.0, in: container) // wide
        XCTAssertEqual(fit.width, 1000, accuracy: 1)
        XCTAssertEqual(fit.height, 500, accuracy: 1)
        XCTAssertEqual(fit.midY, container.midY, accuracy: 1)
    }

    func testAspectFitNeverExceedsContainer() {
        let container = CGRect(x: 10, y: 20, width: 800, height: 1200)
        for aspect in stride(from: 0.2, through: 3.0, by: 0.2) {
            let fit = ScreenshotComposer.aspectFit(aspect: CGFloat(aspect), in: container)
            XCTAssertLessThanOrEqual(fit.width, container.width + 1)
            XCTAssertLessThanOrEqual(fit.height, container.height + 1)
            XCTAssertGreaterThanOrEqual(fit.minX, container.minX - 1)
            XCTAssertGreaterThanOrEqual(fit.minY, container.minY - 1)
        }
    }

    func testAspectFitDegenerateInputsReturnContainer() {
        let container = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(ScreenshotComposer.aspectFit(aspect: 0, in: container), container)
    }

    // MARK: layout — canvas integrity

    func testLayoutCanvasSizeIsPreserved() {
        let style = CanvasStyle()
        let layout = ScreenshotComposer.layout(canvas: canvas, style: style, sourceSize: phoneSource)
        XCTAssertEqual(layout.canvasSize, canvas)
    }

    func testDeviceFitsWithinCanvas() {
        let style = CanvasStyle()
        let layout = ScreenshotComposer.layout(canvas: canvas, style: style, sourceSize: phoneSource)
        XCTAssertGreaterThanOrEqual(layout.deviceRect.minX, 0)
        XCTAssertGreaterThanOrEqual(layout.deviceRect.minY, 0)
        XCTAssertLessThanOrEqual(layout.deviceRect.maxX, canvas.width + 1)
        XCTAssertLessThanOrEqual(layout.deviceRect.maxY, canvas.height + 1)
    }

    func testScreenRectIsInsideDeviceRectWhenFramed() {
        var style = CanvasStyle()
        style.deviceFramed = true
        let layout = ScreenshotComposer.layout(canvas: canvas, style: style, sourceSize: phoneSource)
        XCTAssertGreaterThan(layout.bezelWidth, 0)
        XCTAssertTrue(layout.deviceRect.insetBy(dx: -1, dy: -1).contains(layout.screenRect))
        XCTAssertLessThan(layout.screenRect.width, layout.deviceRect.width)
    }

    func testNoBezelWhenUnframed() {
        var style = CanvasStyle()
        style.deviceFramed = false
        let layout = ScreenshotComposer.layout(canvas: canvas, style: style, sourceSize: phoneSource)
        XCTAssertEqual(layout.bezelWidth, 0)
        XCTAssertEqual(layout.cornerRadius, 0)
        XCTAssertEqual(layout.screenRect, layout.deviceRect)
    }

    // MARK: layout — caption

    func testCaptionTopReservesTopBand() {
        var style = CanvasStyle()
        style.caption.placement = .top
        style.caption.heightFraction = 0.2
        let layout = ScreenshotComposer.layout(canvas: canvas, style: style, sourceSize: phoneSource)
        let caption = try? XCTUnwrap(layout.captionRect)
        XCTAssertEqual(caption?.minY, 0)
        XCTAssertEqual(caption?.height ?? 0, canvas.height * 0.2, accuracy: 1)
        // Device sits below the caption band.
        XCTAssertGreaterThanOrEqual(layout.deviceRect.minY, (caption?.maxY ?? 0) - 1)
    }

    func testCaptionBottomReservesBottomBand() {
        var style = CanvasStyle()
        style.caption.placement = .bottom
        style.caption.heightFraction = 0.18
        let layout = ScreenshotComposer.layout(canvas: canvas, style: style, sourceSize: phoneSource)
        let caption = layout.captionRect
        XCTAssertNotNil(caption)
        XCTAssertEqual(caption!.maxY, canvas.height, accuracy: 1)
        // Device sits above the caption band.
        XCTAssertLessThanOrEqual(layout.deviceRect.maxY, caption!.minY + 1)
    }

    func testCaptionHiddenHasNoRect() {
        var style = CanvasStyle()
        style.caption.placement = .none
        let layout = ScreenshotComposer.layout(canvas: canvas, style: style, sourceSize: phoneSource)
        XCTAssertNil(layout.captionRect)
    }

    // MARK: layout — robustness

    func testZeroSourceFallsBackToCanvasAspect() {
        let style = CanvasStyle()
        let layout = ScreenshotComposer.layout(canvas: canvas, style: style, sourceSize: .zero)
        // Should still produce a sane, non-empty device rect.
        XCTAssertGreaterThan(layout.deviceRect.width, 0)
        XCTAssertGreaterThan(layout.deviceRect.height, 0)
    }

    func testExtremeMarginIsClampedAndStaysValid() {
        var style = CanvasStyle()
        style.marginFraction = 5 // absurd; should clamp
        let layout = ScreenshotComposer.layout(canvas: canvas, style: style, sourceSize: phoneSource)
        XCTAssertGreaterThan(layout.deviceRect.width, 0)
        XCTAssertGreaterThan(layout.deviceRect.height, 0)
    }

    // MARK: device-class framing

    func testFrameProfileMapping() {
        XCTAssertEqual(StatusBarLayoutKind.pad.frameProfile, .iPad)
        XCTAssertEqual(StatusBarLayoutKind.dynamicIsland.frameProfile, .iPhone)
        XCTAssertEqual(StatusBarLayoutKind.notch.frameProfile, .iPhone)
        XCTAssertEqual(StatusBarLayoutKind.classic.frameProfile, .iPhone)
    }

    func testIPadCornersAreLessRoundedThanIPhoneForSameStyle() {
        var style = CanvasStyle()
        style.deviceFramed = true
        style.cornerFraction = 0.05
        let iPadCanvas = CGSize(width: 2064, height: 2752)
        let iPadShot = CGSize(width: 2048, height: 2732)

        let phoneLike = ScreenshotComposer.layout(canvas: iPadCanvas, style: style, sourceSize: iPadShot, profile: .iPhone)
        let padLike = ScreenshotComposer.layout(canvas: iPadCanvas, style: style, sourceSize: iPadShot, profile: .iPad)

        XCTAssertLessThan(padLike.cornerRadius, phoneLike.cornerRadius)
        XCTAssertGreaterThan(padLike.cornerRadius, 0)
    }

    func testIPadProfileStillKeepsScreenInsideDevice() {
        var style = CanvasStyle()
        style.deviceFramed = true
        let iPadCanvas = CGSize(width: 2064, height: 2752)
        let layout = ScreenshotComposer.layout(canvas: iPadCanvas, style: style,
                                               sourceSize: CGSize(width: 2048, height: 2732), profile: .iPad)
        XCTAssertGreaterThan(layout.bezelWidth, 0)
        XCTAssertTrue(layout.deviceRect.insetBy(dx: -1, dy: -1).contains(layout.screenRect))
        XCTAssertLessThanOrEqual(layout.deviceRect.maxX, iPadCanvas.width + 1)
        XCTAssertLessThanOrEqual(layout.deviceRect.maxY, iPadCanvas.height + 1)
    }

    func testCaptionFontScalesWithCanvasWidth() {
        var style = CanvasStyle()
        style.caption.sizeFraction = 0.07
        let small = ScreenshotComposer.layout(canvas: CGSize(width: 1242, height: 2208), style: style, sourceSize: phoneSource)
        let large = ScreenshotComposer.layout(canvas: CGSize(width: 2064, height: 2752), style: style, sourceSize: phoneSource)
        XCTAssertGreaterThan(large.captionFontSize, small.captionFontSize)
        XCTAssertEqual(small.captionFontSize, 1242 * 0.07, accuracy: 1)
    }
}
