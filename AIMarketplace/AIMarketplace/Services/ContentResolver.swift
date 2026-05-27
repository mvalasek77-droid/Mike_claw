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

    /// Full manuscript text for a novel, from a bundled `<slug>.txt`.
    static func bookText(for item: MediaItem) -> String? {
        guard item.type == .novel, let name = item.mediaFileName ?? item.coverAssetName else { return nil }
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Samples")
                ?? Bundle.main.url(forResource: name, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func mediaURL(for item: MediaItem) -> URL? {
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
