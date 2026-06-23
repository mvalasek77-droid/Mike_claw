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
        guard let data = image.pngData() else {
            BugLog.error("ImageStore", "Couldn't encode an imported image to PNG.")
            return nil
        }
        do {
            try data.write(to: url, options: .atomic)
            cache.setObject(image, forKey: name as NSString)
            return name
        } catch {
            BugLog.error("ImageStore", "Failed to save image: \(error.localizedDescription)")
            return nil
        }
    }

    /// Load a previously saved image by file name.
    static func load(_ name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let url = Workspace.imagesDirectory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            BugLog.warning("ImageStore", "Missing or unreadable image file: \(name)")
            return nil
        }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// Duplicate a stored image file, returning the new file name. Used when
    /// duplicating a set or slide so each copy owns its own source image and
    /// deleting one never removes another's file.
    @discardableResult
    static func copy(_ name: String) -> String? {
        let newName = "shot-\(UUID().uuidString).png"
        let src = Workspace.imagesDirectory.appendingPathComponent(name)
        let dst = Workspace.imagesDirectory.appendingPathComponent(newName)
        do {
            try Workspace.fileManager.copyItem(at: src, to: dst)
            return newName
        } catch {
            // The raw file may be gone (only the in-memory cache has it) — fall
            // back to re-encoding a loaded copy before giving up.
            if let image = load(name) { return save(image) }
            BugLog.error("ImageStore", "Couldn't duplicate image \(name): \(error.localizedDescription)")
            return nil
        }
    }

    /// Remove an image file (best-effort) and drop it from the cache.
    static func delete(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        let url = Workspace.imagesDirectory.appendingPathComponent(name)
        try? Workspace.fileManager.removeItem(at: url)
    }
}
