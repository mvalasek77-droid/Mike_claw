import SwiftUI

/// An in-memory cache of rendered gallery thumbnails. Keyed by the project's
/// identity *and* its modification time + representative slide, so an edit
/// naturally invalidates the stale thumbnail without any manual bookkeeping.
/// `NSCache` is thread-safe and the key is pure, so this needs no isolation.
enum ThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func key(for project: ScreenshotProject) -> String {
        let slide = project.slides.first?.id.uuidString ?? "empty"
        return "\(project.id.uuidString)|\(project.modifiedAt.timeIntervalSinceReferenceDate)|\(slide)|\(project.slides.count)|\(project.activeLanguage)"
    }

    static func image(for project: ScreenshotProject) -> UIImage? {
        cache.object(forKey: key(for: project) as NSString)
    }

    static func store(_ image: UIImage?, for project: ScreenshotProject) {
        guard let image else { return }
        cache.setObject(image, forKey: key(for: project) as NSString)
    }
}

/// A gallery card's preview image. Renders the project's first slide through
/// the real `ScreenshotCanvas` (so it's genuinely WYSIWYG), but rasterizes the
/// result and caches it — fast to scroll and never blank, unlike live-scaling
/// a full-resolution canvas inside a lazy grid cell.
struct ProjectThumbnail: View {
    let project: ScreenshotProject

    @State private var image: UIImage?

    private var aspect: CGFloat {
        let s = project.deviceSize.pixelSize(for: project.orientation)
        return s.height == 0 ? 0.5 : s.width / s.height
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // A tasteful placeholder in the set's own backdrop while the
                // thumbnail renders — never a blank white/black void.
                Rectangle()
                    .fill(project.style.background.shapeStyle)
                    .overlay(
                        ProgressView()
                            .tint(LiquidGlass.accent)
                    )
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: ThumbnailCache.key(for: project)) {
            await render()
        }
    }

    @MainActor
    private func render() async {
        if let cached = ThumbnailCache.image(for: project) {
            image = cached
            return
        }
        // Let the placeholder paint first, then rasterize off the first frame.
        await Task.yield()
        guard !Task.isCancelled else { return }
        let rendered = ScreenshotRenderer.thumbnail(of: project, slide: project.slides.first)
        if rendered == nil {
            BugLog.warning("Thumbnail", "Couldn't render a thumbnail for “\(project.name)”.")
        }
        ThumbnailCache.store(rendered, for: project)
        image = rendered
    }
}
