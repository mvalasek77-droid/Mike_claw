import Foundation

/// The signed-in identity. A single source of truth so composer-authored posts,
/// the profile screen, and "OP" highlighting all agree on who "you" are.
/// Backed by a stable UUID so mock data linking to "me" stays consistent.
enum Session {
    static let me = User(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B0")!,
        handle: "@you",
        displayName: "You",
        avatarURL: nil,
        broCred: 1_280
    )
}
