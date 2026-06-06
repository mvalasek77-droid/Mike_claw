import UIKit

/// Reads and writes source screenshots to the workspace. We persist as PNG to
/// preserve crisp UI screenshots losslessly, and cache decoded images in
/// memory so scrolling a project never thrashes the disk.
enum ImageStore {
    private static let cache = NSCache<NSString, UIImage>()

    /// Save an image and return the file name to store on the slide.
    @discardableResult
    static func save(_ image: UIImage) -> String? {
        let name = "shot-\(UUID().uuidString).png"
        let url = Workspace.imagesDirectory.appendingPathComponent(name)
        guard let data = image.pngData() else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            cache.setObject(image, forKey: name as NSString)
            return name
        } catch {
            return nil
        }
    }

    /// Load a previously saved image by file name.
    static func load(_ name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let url = Workspace.imagesDirectory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// Remove an image file (best-effort) and drop it from the cache.
    static func delete(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        let url = Workspace.imagesDirectory.appendingPathComponent(name)
        try? Workspace.fileManager.removeItem(at: url)
    }
}
