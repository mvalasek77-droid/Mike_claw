import Foundation

/// God-mode credentials. These gate the admin console (add / adjust / delete any
/// media, reset the catalogue). This is a local, single-owner gate for the
/// prototype — change these before sharing the build, and note that real
/// god-mode auth belongs server-side, tied to the verified owner account.
enum Admin {
    static let username = "valasek"
    static let password = "Odyssey-NRN-2026"

    static func validate(username: String, password: String) -> Bool {
        username.trimmingCharacters(in: .whitespaces).lowercased() == Admin.username
            && password == Admin.password
    }
}
