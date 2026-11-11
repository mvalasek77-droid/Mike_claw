import Foundation
import Security
import CryptoKit

/// The companion's own TLS identity.
///
/// The phone sends the App Store Connect signing key over this link, so
/// it cannot be plain TCP. There is no certificate authority for a Mac
/// on a home network, so the companion makes a self-signed certificate
/// once and shows its fingerprint in the pairing code. The phone then
/// accepts that certificate and no other.
///
/// The key pair is generated with the system's own `openssl` and kept
/// in Application Support, readable only by the user. It is created
/// once: regenerating it would silently unpair every phone.
enum TLSIdentity {

    struct Loaded {
        let identity: SecIdentity
        /// SHA-256 of the certificate's DER bytes, lowercase hex.
        let fingerprint: String
    }

    enum Failure: Error, CustomStringConvertible {
        case tool(String)
        case importFailed(OSStatus)
        case noIdentity

        var description: String {
            switch self {
            case .tool(let detail): "could not create the companion's certificate: \(detail)"
            case .importFailed(let status): "could not load the companion's certificate (status \(status))"
            case .noIdentity: "the companion's certificate file contains no identity"
            }
        }
    }

    private static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("CodeGenie", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir
    }

    private static var bundleURL: URL { directory.appendingPathComponent("companion-identity.p12") }
    private static var passphraseURL: URL { directory.appendingPathComponent("companion-identity.pass") }

    static func loadOrCreate() throws -> Loaded {
        if FileManager.default.fileExists(atPath: bundleURL.path),
           let loaded = try? load() {
            return loaded
        }
        try create()
        return try load()
    }

    /// Lowercase hex SHA-256 of a certificate's DER encoding. The same
    /// calculation the phone does on the certificate it is offered.
    static func fingerprint(ofDER der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Internals

    private static func load() throws -> Loaded {
        let data = try Data(contentsOf: bundleURL)
        let passphrase = try String(contentsOf: passphraseURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var items: CFArray?
        let options = [kSecImportExportPassphrase as String: passphrase] as CFDictionary
        let status = SecPKCS12Import(data as CFData, options, &items)
        guard status == errSecSuccess else { throw Failure.importFailed(status) }
        guard let first = (items as? [[String: Any]])?.first,
              let raw = first[kSecImportItemIdentity as String]
        else { throw Failure.noIdentity }
        // The dictionary is typed `Any`; the value under this key is
        // documented to be a SecIdentity.
        let identity = raw as! SecIdentity

        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
              let certificate
        else { throw Failure.noIdentity }
        let der = SecCertificateCopyData(certificate) as Data
        return Loaded(identity: identity, fingerprint: fingerprint(ofDER: der))
    }

    private static func create() throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("codegenie-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: work, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // The private key exists unencrypted only inside this folder,
        // and the folder goes whatever happens next.
        defer { try? FileManager.default.removeItem(at: work) }

        let key = work.appendingPathComponent("key.pem").path
        let cert = work.appendingPathComponent("cert.pem").path
        let bundle = work.appendingPathComponent("identity.p12").path

        let passphrase = (0..<24).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()

        try run([
            "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", key, "-out", cert,
            "-days", "3650", "-subj", "/CN=CodeGenie Companion",
        ])
        try run([
            "pkcs12", "-export", "-inkey", key, "-in", cert,
            "-out", bundle, "-name", "CodeGenie Companion",
            "-passout", "pass:\(passphrase)",
        ])

        let owner: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        try Data(contentsOf: URL(fileURLWithPath: bundle)).write(to: bundleURL, options: .atomic)
        try FileManager.default.setAttributes(owner, ofItemAtPath: bundleURL.path)
        try Data(passphrase.utf8).write(to: passphraseURL, options: .atomic)
        try FileManager.default.setAttributes(owner, ofItemAtPath: passphraseURL.path)
    }

    private static func run(_ arguments: [String]) throws {
        let process = Process()
        // The copy that ships with macOS. Its PKCS#12 output is the
        // form `SecPKCS12Import` reads.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Failure.tool(String(detail.suffix(300)))
        }
    }
}
