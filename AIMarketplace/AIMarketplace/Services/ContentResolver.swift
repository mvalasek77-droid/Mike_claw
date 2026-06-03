import SwiftUI

/// Resolves cover art and playable media for a title.
///
/// Resolution order:
/// 1. Creator-uploaded data carried on the `MediaItem` (user-published titles).
/// 2. A bundled asset named after the item's slug (seed catalogue + your own
///    samples — drop files into `Resources/Samples`, see that folder's README).
/// 3. `nil`, in which case the UI falls back to procedural art / a simulated
///    playhead so the app is always functional even before assets are added.
enum ContentResolver {

    // MARK: Cover art

    static func coverImage(for item: MediaItem) -> UIImage? {
        if let data = item.coverImageData, let image = UIImage(data: data) { return image }
        if let name = item.coverAssetName { return bundledImage(named: name) }
        return nil
    }

    /// A UIImage cover for lock-screen artwork: the supplied/bundled image if
    /// present, otherwise a snapshot of the procedurally generated cover.
    @MainActor
    static func artworkImage(for item: MediaItem, size: CGFloat = 600) -> UIImage? {
        if let image = coverImage(for: item) { return image }
        let renderer = ImageRenderer(content:
            GeneratedCover(item: item).frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.06)))
        renderer.scale = 2
        return renderer.uiImage
    }

    static func bundledImage(named name: String) -> UIImage? {
        if let asset = UIImage(named: name) { return asset }
        for ext in ["jpg", "jpeg", "png", "heic"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Samples")
                ?? Bundle.main.url(forResource: name, withExtension: ext),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }

    // MARK: Playable media

    /// Full manuscript text for a novel. Resolution order:
    /// 1. The user's uploaded manuscript carried directly on the MediaItem
    ///    (set by MarketplaceStore.publish for user-published titles).
    /// 2. A bundled `<slug>.txt` keyed by mediaFileName or coverAssetName
    ///    (seed catalogue + operator-supplied samples).
    static func bookText(for item: MediaItem) -> String? {
        guard item.type == .novel else { return nil }
        if let text = item.manuscriptText, !text.isEmpty { return text }
        guard let name = item.mediaFileName ?? item.coverAssetName else { return nil }
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Samples")
                ?? Bundle.main.url(forResource: name, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Playable URL for music/movie. Resolution order:
    /// 1. User-published file at `Documents/published/<localMediaFileName>`
    ///    (MarketplaceStore.publish copies the upload here so it survives the
    ///    picker's security-scoped lifetime).
    /// 2. A bundled asset named by `mediaFileName` (seed catalogue).
    static func mediaURL(for item: MediaItem) -> URL? {
        if let basename = item.localMediaFileName,
           let docs = try? FileManager.default.url(for: .documentDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: false) {
            let candidate = docs.appendingPathComponent("published", isDirectory: true)
                                .appendingPathComponent(basename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        guard let name = item.mediaFileName else { return nil }
        let extensions: [String]
        switch item.type {
        case .music: extensions = ["m4a", "mp3", "aac", "wav"]
        case .movie: extensions = ["mp4", "mov", "m4v"]
        case .novel: return nil
        }
        for ext in extensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Samples")
                ?? Bundle.main.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}
