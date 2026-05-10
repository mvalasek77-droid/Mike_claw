import Foundation

/// Persists the pairing token at
/// `~/Library/Application Support/CodeGenie/companion.token` so the
/// daemon can be restarted without re-pairing the iPhone.
///
/// We deliberately do **not** put this in the keychain — the daemon
/// runs unattended and the token has no value off the user's machine
/// (the WebSocket only listens on local interfaces). 0600 perms on the
/// file are sufficient.
enum TokenStore {
    private static var path: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("CodeGenie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("companion.token")
    }

    static func loadOrCreate() -> String {
        if let data = try? Data(contentsOf: path),
           let s = String(data: data, encoding: .utf8),
           !s.isEmpty {
            return s
        }
        let token = generate()
        try? token.data(using: .utf8)?.write(to: path, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        return token
    }

    static func rotate() -> String {
        try? FileManager.default.removeItem(at: path)
        return loadOrCreate()
    }

    private static func generate() -> String {
        let bytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
