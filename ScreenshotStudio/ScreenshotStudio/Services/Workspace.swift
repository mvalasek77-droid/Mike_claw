import Foundation

/// Centralises the on-disk locations Screenshot Studio writes to. Everything
/// lives under Application Support so it's backed up but hidden from the
/// user's Files browser, and survives app updates.
enum Workspace {
    static let fileManager = FileManager.default

    static var root: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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

    /// Create a directory if it doesn't already exist. Failures here are
    /// non-fatal: persistence simply degrades to in-memory for the session.
    private static func ensure(_ url: URL) {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
