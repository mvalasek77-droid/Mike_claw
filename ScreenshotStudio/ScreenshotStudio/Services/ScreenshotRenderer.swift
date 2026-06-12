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
                       captionText: String,
                       statusBarLayout: StatusBarLayoutKind) -> UIImage? {
        let canvas = ScreenshotCanvas(
            canvasSize: canvasSize,
            style: style,
            image: image,
            captionText: captionText,
            statusBarLayout: statusBarLayout
        )
        .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(canvasSize)
        renderer.isOpaque = true
        let image = renderer.uiImage
        if image == nil {
            BugLog.error("Renderer", "ImageRenderer produced no image at \(Int(canvasSize.width))×\(Int(canvasSize.height)).")
        }
        return image
    }

    /// Render a small, cache-friendly thumbnail of a project's representative
    /// slide. We rasterize at a modest scale rather than live-scaling a full
    /// 1320×2868 canvas inside every grid cell — that keeps the gallery fast
    /// and, crucially, never renders blank under lazy layout.
    static func thumbnail(of project: ScreenshotProject,
                          slide: Slide?,
                          targetWidth: CGFloat = 320) -> UIImage? {
        let canvasSize = project.deviceSize.pixelSize(for: project.orientation)
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let source = slide.flatMap { ImageStore.load($0.imageFile) }
        let caption = slide.map { project.captionText(for: $0) } ?? project.style.caption.text
        let canvas = ScreenshotCanvas(
            canvasSize: canvasSize,
            style: project.style,
            image: source,
            captionText: caption,
            statusBarLayout: project.deviceSize.statusBarLayout
        )
        .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = max(targetWidth / canvasSize.width, 0.05)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Render every slide of a project for a single device slot.
    static func renderSlides(of project: ScreenshotProject,
                             for device: ASCDeviceSize) -> [UIImage] {
        let canvasSize = device.pixelSize(for: project.orientation)
        let layout = device.statusBarLayout
        return project.slides.compactMap { slide in
            let source = ImageStore.load(slide.imageFile)
            return render(canvasSize: canvasSize,
                          style: project.style,
                          image: source,
                          captionText: project.captionText(for: slide),
                          statusBarLayout: layout)
        }
    }

    /// Async variant that yields between slides so a multi-slide share render
    /// doesn't freeze the main run loop while the UI shows a "preparing" state.
    static func renderSlidesAsync(of project: ScreenshotProject,
                                  for device: ASCDeviceSize) async -> [UIImage] {
        let canvasSize = device.pixelSize(for: project.orientation)
        let layout = device.statusBarLayout
        var out: [UIImage] = []
        out.reserveCapacity(project.slides.count)
        for slide in project.slides {
            if let image = render(canvasSize: canvasSize,
                                  style: project.style,
                                  image: ImageStore.load(slide.imageFile),
                                  captionText: project.captionText(for: slide),
                                  statusBarLayout: layout) {
                out.append(image)
            }
            await Task.yield()
        }
        return out
    }

    /// Render every slide across every selected slot and language — used by the
    /// share path so "Share PNGs" hands off the complete export, not just the
    /// primary size in one language.
    static func renderAllAsync(of project: ScreenshotProject,
                               sizes: [ASCDeviceSize],
                               languages: [String]) async -> [UIImage] {
        let slots = sizes.isEmpty ? [project.deviceSize] : sizes
        let langs = languages.isEmpty ? [project.activeLanguage] : languages
        var out: [UIImage] = []
        out.reserveCapacity(slots.count * langs.count * project.slides.count)
        for slot in slots {
            let canvasSize = slot.pixelSize(for: project.orientation)
            let layout = slot.statusBarLayout
            for lang in langs {
                for slide in project.slides {
                    if let image = render(canvasSize: canvasSize,
                                          style: project.style,
                                          image: ImageStore.load(slide.imageFile),
                                          captionText: project.captionText(for: slide, language: lang),
                                          statusBarLayout: layout) {
                        out.append(image)
                    }
                    await Task.yield()
                }
            }
        }
        return out
    }
}
