import Foundation

/// Everything the phone needs to find and trust one Mac.
///
/// Comes from the pairing code the companion shows, as a URL:
/// `codegenie://pair?host=…&port=…&token=…&fp=…`
///
/// The fingerprint is not optional. The companion's certificate is
/// self-signed, so the fingerprint in the code — read off the Mac's
/// own screen — is the only thing that proves the machine answering
/// on the network is that Mac. The signing key for the user's Apple
/// account crosses this connection; an unpinned one is not offered.
struct MacPairing: Codable, Equatable {
    let host: String
    let port: UInt16
    let token: String
    /// SHA-256 of the companion's certificate, lowercase hex.
    let fingerprint: String

    enum ParseError: Error, Equatable {
        case notAPairingCode
        case missing(String)
        case badPort
        case badFingerprint
        /// A code from a companion that predates encrypted pairing.
        case outdatedCompanion

        var message: String {
            switch self {
            case .notAPairingCode:
                "That isn't a CodeGenie pairing code. Scan the code shown by the companion on your Mac."
            case .missing(let part):
                "The pairing code is incomplete (no \(part)). Scan it again from your Mac."
            case .badPort:
                "The pairing code has an invalid port. Restart the companion on your Mac and scan the new code."
            case .badFingerprint:
                "The pairing code is damaged. Scan it again from your Mac."
            case .outdatedCompanion:
                "This code is from an older companion that can't make a secure connection. Update the companion on your Mac, then scan its new code."
            }
        }
    }

    static func parse(_ text: String) -> Result<MacPairing, ParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "codegenie",
              components.host?.lowercased() == "pair"
        else { return .failure(.notAPairingCode) }

        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value, !value.isEmpty { values[item.name] = value }
        }

        guard let host = values["host"] else { return .failure(.missing("host")) }
        guard let portText = values["port"] else { return .failure(.missing("port")) }
        guard let port = UInt16(portText), port > 0 else { return .failure(.badPort) }
        guard let token = values["token"] else { return .failure(.missing("token")) }
        guard let rawFingerprint = values["fp"] else { return .failure(.outdatedCompanion) }

        let fingerprint = normalise(fingerprint: rawFingerprint)
        guard fingerprint.count == 64 else { return .failure(.badFingerprint) }

        return .success(MacPairing(host: host, port: port, token: token, fingerprint: fingerprint))
    }

    /// Lowercase hex with separators removed, so `AB:CD…` and `abcd…`
    /// compare equal.
    static func normalise(fingerprint: String) -> String {
        String(fingerprint.lowercased().filter { $0.isHexDigit })
    }

    /// Whether a certificate with this digest is the paired Mac's.
    func matches(certificateDigest hex: String) -> Bool {
        let candidate = Self.normalise(fingerprint: hex)
        guard candidate.count == fingerprint.count else { return false }
        // Compared without an early exit. The value isn't secret, but
        // there is no reason to make this the one comparison that leaks
        // how much of it matched.
        var difference: UInt8 = 0
        for (a, b) in zip(candidate.utf8, fingerprint.utf8) { difference |= a ^ b }
        return difference == 0
    }
}
