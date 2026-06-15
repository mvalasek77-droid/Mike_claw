import Foundation

/// Centralises the on-disk locations Screenshot Studio writes to. Everything
/// lives under Application Support so it's backed up but hidden from the
/// user's Files browser, and survives app updates.
enum Workspace {
    static let fileManager = FileManager.default

    static var root: URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not available")
        }
        let dir = base.appendingPathComponent("ScreenshotStudio", isDirectory: true)
        ensure(dir)
        return dir
    }

    static var imagesDirectory: URL {
        let dir = root.appendingPathComponent("Images", isDirectory: true)
        ensure(dir)
        return dir
    }

    static var projectsFile: URL {
        root.appendingPathComponent("projects.json", isDirectory: false)
    }

    /// Total bytes used by stored source images.
    static func imagesDirectorySize() -> Int64 {
        let urls = (try? fileManager.contentsOfDirectory(
            at: imagesDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    /// Create a directory if it doesn't already exist. Failures here are
    /// non-fatal: persistence simply degrades to in-memory for the session.
    private static func ensure(_ url: URL) {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
