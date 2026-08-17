import Foundation

/// Resolves the published location of the daily-regenerated avatars (see
/// `tools/metabro_assets` and the `MetaBro Avatars (daily)` workflow). Views can
/// feed these URLs into `AsyncImage`; the cron refreshes the images each day, so
/// the app picks up new art without a release.
enum AvatarCatalog {
    /// Where the daily avatar PNGs are served from. Point this at a CDN in
    /// production; the repo's raw path is a sensible default for the demo.
    /// `let` keeps it concurrency-safe under Swift 6 strict concurrency.
    static let base = URL(string:
        "https://raw.githubusercontent.com/mvalasek77-droid/Mike_claw/"
        + "claude/metabro-facebook-reddit-hybrid-it80pk/MetaBro/Branding/avatars/")!

    /// Avatar URL for a user, keyed by handle ("@ironbro" or "ironbro").
    static func user(handle: String) -> URL {
        base.appendingPathComponent(key(handle) + ".png")
    }

    /// Icon URL for a Bro-hood, keyed by its slug ("fitness").
    static func community(slug: String) -> URL {
        base.appendingPathComponent(slug + ".png")
    }

    /// Normalizes a handle to its file stem (drops a leading "@", lowercases).
    static func key(_ handle: String) -> String {
        (handle.hasPrefix("@") ? String(handle.dropFirst()) : handle).lowercased()
    }
}
