import SwiftUI

/// Renders a `ScreenshotCanvas` off-screen to a pixel-exact `UIImage`.
///
/// We drive `ImageRenderer` at `scale = 1` with a proposed size equal to the
/// target resolution, so a 1320×2868 slot produces a 1320×2868 PNG — no
/// Retina multiplier surprises, which is exactly what App Store Connect's
/// validator wants.
@MainActor
enum ScreenshotRenderer {

    /// Render a single slide to an image at the slot's resolution.
    static func render(canvasSize: CGSize,
                       style: CanvasStyle,
                       image: UIImage?,
                       captionText: String) -> UIImage? {
        let canvas = ScreenshotCanvas(
            canvasSize: canvasSize,
            style: style,
            image: image,
            captionText: captionText
        )
        .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(canvasSize)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Render every slide of a project for a single device slot.
    static func renderSlides(of project: ScreenshotProject,
                             for device: ASCDeviceSize) -> [UIImage] {
        let canvasSize = device.pixelSize(for: project.orientation)
        return project.slides.compactMap { slide in
            let source = ImageStore.load(slide.imageFile)
            return render(canvasSize: canvasSize,
                          style: project.style,
                          image: source,
                          captionText: project.captionText(for: slide))
        }
    }
}
