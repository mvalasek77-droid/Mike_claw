import CoreGraphics
import Foundation

/// The geometry of a composed screenshot, expressed entirely in the target
/// canvas's pixel space. Every rect is ready to hand to a renderer.
struct ComposedLayout: Equatable {
    /// Full canvas in pixels (matches the App Store Connect slot exactly).
    var canvasSize: CGSize
    /// Where the caption text is laid out, or `nil` when the caption is hidden.
    var captionRect: CGRect?
    /// Outer bounds of the device (bezel included).
    var deviceRect: CGRect
    /// The screen opening where the source screenshot is drawn.
    var screenRect: CGRect
    /// Corner radius of the screen opening, in pixels.
    var cornerRadius: CGFloat
    /// Bezel thickness in pixels (0 when the device frame is disabled).
    var bezelWidth: CGFloat
    /// Caption font size in points (== pixels at render scale 1).
    var captionFontSize: CGFloat
}

/// Pure, deterministic layout engine. Given a target canvas and a style, it
/// computes exactly where the caption, device and screenshot land. Keeping
/// this free of UIKit/SwiftUI is what lets us pin the behaviour down with
/// fast unit tests and reuse the identical math for both live preview and
/// off-screen export.
enum ScreenshotComposer {

    /// Aspect-fit `aspect` (width / height) centred inside `container`.
    static func aspectFit(aspect: CGFloat, in container: CGRect) -> CGRect {
        guard aspect > 0, container.width > 0, container.height > 0 else { return container }
        let containerAspect = container.width / container.height
        var size = container.size
        if aspect > containerAspect {
            // Source is wider — width-bound.
            size.width = container.width
            size.height = container.width / aspect
        } else {
            // Source is taller — height-bound.
            size.height = container.height
            size.width = container.height * aspect
        }
        let origin = CGPoint(
            x: container.minX + (container.width - size.width) / 2,
            y: container.minY + (container.height - size.height) / 2
        )
        return CGRect(origin: origin, size: size).integral
    }

    /// Compute the full layout for a canvas.
    ///
    /// - Parameters:
    ///   - canvas: target pixel size (an `ASCDeviceSize` slot resolution).
    ///   - style: the user's composition settings.
    ///   - sourceSize: pixel size of the imported screenshot. When `.zero`,
    ///     the layout falls back to the canvas aspect ratio so a placeholder
    ///     still composes sensibly.
    static func layout(canvas: CGSize, style: CanvasStyle, sourceSize: CGSize) -> ComposedLayout {
        let canvasRect = CGRect(origin: .zero, size: canvas)

        // --- Caption region ----------------------------------------------
        let captionFraction = clamp(style.caption.heightFraction, 0, 0.45)
        let showCaption = style.caption.placement != .none
        let captionHeight = showCaption ? canvas.height * captionFraction : 0

        var captionRect: CGRect?
        var contentRect = canvasRect
        if showCaption {
            switch style.caption.placement {
            case .top:
                captionRect = CGRect(x: 0, y: 0, width: canvas.width, height: captionHeight)
                contentRect = CGRect(x: 0, y: captionHeight,
                                     width: canvas.width, height: canvas.height - captionHeight)
            case .bottom:
                captionRect = CGRect(x: 0, y: canvas.height - captionHeight,
                                     width: canvas.width, height: captionHeight)
                contentRect = CGRect(x: 0, y: 0,
                                     width: canvas.width, height: canvas.height - captionHeight)
            case .none:
                break
            }
        }

        // --- Device region -----------------------------------------------
        let margin = canvas.width * clamp(style.marginFraction, 0, 0.35)
        let deviceContainer = contentRect.insetBy(dx: margin, dy: margin)

        // The screenshot's own aspect ratio drives the device shape; fall
        // back to the canvas ratio for an empty slide.
        let aspect: CGFloat
        if sourceSize.width > 0, sourceSize.height > 0 {
            aspect = sourceSize.width / sourceSize.height
        } else {
            aspect = canvas.height == 0 ? 1 : canvas.width / canvas.height
        }

        let deviceRect = aspectFit(aspect: aspect, in: deviceContainer)

        // Thin, modern bezel proportional to canvas width.
        let bezel = style.deviceFramed ? max(canvas.width * 0.013, 4).rounded() : 0
        let screenRect = deviceRect.insetBy(dx: bezel, dy: bezel)

        let corner = style.deviceFramed
            ? min(canvas.width * clamp(style.cornerFraction, 0, 0.25), min(screenRect.width, screenRect.height) / 2)
            : 0

        let captionFont = (canvas.width * clamp(style.caption.sizeFraction, 0.02, 0.18)).rounded()

        return ComposedLayout(
            canvasSize: canvas,
            captionRect: captionRect,
            deviceRect: deviceRect,
            screenRect: screenRect,
            cornerRadius: corner,
            bezelWidth: bezel,
            captionFontSize: captionFont
        )
    }

    private static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        min(max(v, lo), hi)
    }
}
