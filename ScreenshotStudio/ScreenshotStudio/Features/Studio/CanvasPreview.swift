import SwiftUI

/// Scales a full-resolution `ScreenshotCanvas` down to fit an arbitrary box,
/// preserving the exact composition. Because it reuses the same canvas the
/// exporter renders, the preview is genuinely WYSIWYG — never an
/// approximation. Used for both the editor's hero preview and grid thumbnails.
struct CanvasPreview: View {
    let canvasSize: CGSize
    let style: CanvasStyle
    let image: UIImage?
    let captionText: String
    var statusBarLayout: StatusBarLayoutKind = .dynamicIsland

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / canvasSize.width,
                            geo.size.height / canvasSize.height)
            ScreenshotCanvas(
                canvasSize: canvasSize,
                style: style,
                image: image,
                captionText: captionText,
                statusBarLayout: statusBarLayout
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: canvasSize.width * scale, height: canvasSize.height * scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(canvasSize.width / canvasSize.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension CanvasPreview {
    /// Convenience for previewing a project's slide.
    init(project: ScreenshotProject, slide: Slide?) {
        self.canvasSize = project.deviceSize.pixelSize(for: project.orientation)
        self.style = project.style
        self.image = slide.flatMap { ImageStore.load($0.imageFile) }
        self.captionText = slide.map { project.captionText(for: $0) } ?? project.style.caption.text
        self.statusBarLayout = project.deviceSize.statusBarLayout
    }
}
