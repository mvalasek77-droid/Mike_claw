import Foundation

/// Persists the pairing token at
/// `~/Library/Application Support/CodeGenie/companion.token` so the
/// daemon can be restarted without re-pairing the iPhone.
///
/// We deliberately do **not** put this in the keychain — the daemon
/// runs unattended. NOTE the honest threat model: the listener binds
/// all interfaces and advertises over Bonjour so the iPhone can reach
/// it across the LAN, and there is no TLS — so this token IS the only
/// thing standing between anyone on the same Wi-Fi and the companion's
/// commands (open Xcode, fill ASC pages). 0600 file perms protect it
/// at rest; treat shared/untrusted networks accordingly.
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
