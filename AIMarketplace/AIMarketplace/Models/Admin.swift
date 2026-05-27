import Foundation

/// God-mode configuration. The passcode gates the admin console (add / adjust /
/// delete any media). Change this before shipping; in production this check
/// belongs server-side, tied to the owner account.
enum Admin {
    static let passcode = "valasek"
}
