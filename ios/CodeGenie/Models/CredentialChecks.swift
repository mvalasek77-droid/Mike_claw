import Foundation

/// Catches the mistakes people make copying credentials between
/// websites and a phone, before those mistakes surface minutes later
/// as an error from Apple that reads like the app is broken.
///
/// Every check here is about shape, not validity: only the provider
/// can say whether a key works. Shape checks are still worth having
/// because nearly every real failure is a paste gone wrong.
enum CredentialCheck {

    enum Verdict: Equatable {
        case ok
        /// Unusual but possibly right. Let the user continue.
        case warning(String)
        /// Cannot be right. Don't save it.
        case invalid(String)

        var isUsable: Bool {
            if case .invalid = self { return false }
            return true
        }

        var message: String? {
            switch self {
            case .ok: nil
            case .warning(let text), .invalid(let text): text
            }
        }
    }

    /// Strip what copying adds: surrounding space, quotes, a trailing
    /// newline.
    static func tidy(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: AI provider keys

    static func providerKey(_ raw: String, for provider: AIProvider) -> Verdict {
        let key = tidy(raw)
        if key.isEmpty { return .invalid("Paste your \(provider.displayName) key here.") }
        if key.contains(where: { $0.isWhitespace }) {
            return .invalid("There's a space or line break inside the key. Copy it again in one piece.")
        }
        if key.count < 20 {
            return .invalid("That's too short to be a \(provider.displayName) key. Copy the whole thing.")
        }
        switch provider {
        case .anthropic:
            if key.hasPrefix("sk-ant-") { return .ok }
            if key.hasPrefix("sk-") {
                return .invalid("That looks like an OpenAI key. Anthropic keys start with sk-ant-.")
            }
            return .warning("Anthropic keys normally start with sk-ant-. Check you copied the right thing.")
        case .openai:
            if key.hasPrefix("sk-ant-") {
                return .invalid("That's an Anthropic key. Paste it in the Anthropic box instead.")
            }
            if key.hasPrefix("sk-") { return .ok }
            return .warning("OpenAI keys normally start with sk-. Check you copied the right thing.")
        }
    }

    // MARK: Apple identifiers

    /// A Team ID is ten letters and digits, e.g. `ABCD123456`.
    static func teamID(_ raw: String) -> Verdict {
        let id = tidy(raw).uppercased()
        if id.isEmpty { return .invalid("Enter your Team ID.") }
        if id.contains("@") {
            return .invalid("That's an email address. The Team ID is a 10-character code on the Membership page.")
        }
        guard id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return .invalid("A Team ID is only letters and numbers — no spaces or punctuation.")
        }
        if id.count != 10 {
            return .invalid("A Team ID is exactly 10 characters. This is \(id.count).")
        }
        return .ok
    }

    /// An App Store Connect key ID, e.g. `2X9R4HXF34`.
    static func keyID(_ raw: String) -> Verdict {
        let id = tidy(raw).uppercased()
        if id.isEmpty { return .invalid("Enter the Key ID.") }
        guard id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return .invalid("A Key ID is only letters and numbers.")
        }
        if UUID(uuidString: tidy(raw)) != nil {
            return .invalid("That's the Issuer ID. The Key ID is the short code next to your key's name.")
        }
        if id.count != 10 {
            return .warning("Key IDs are normally 10 characters. This is \(id.count) — double-check it.")
        }
        return .ok
    }

    /// The Issuer ID is a UUID shown above the list of keys.
    static func issuerID(_ raw: String) -> Verdict {
        let id = tidy(raw)
        if id.isEmpty { return .invalid("Enter the Issuer ID.") }
        if UUID(uuidString: id) == nil {
            return .invalid("The Issuer ID is a long code with four dashes, like 57246542-96fe-1a63-e053-0824d011072a. It's above the list of keys, not next to one.")
        }
        return .ok
    }

    /// Key IDs are in the name of the file Apple gives you:
    /// `AuthKey_2X9R4HXF34.p8`.
    static func keyID(fromFileName name: String) -> String? {
        let base = (name as NSString).lastPathComponent
        guard base.lowercased().hasSuffix(".p8"), base.hasPrefix("AuthKey_") else { return nil }
        let id = String(base.dropFirst("AuthKey_".count).dropLast(3))
        return keyID(id) == .ok ? id.uppercased() : nil
    }

    // MARK: The .p8 private key

    /// Rebuild a private key into the exact form the signing code
    /// reads, or nil if it isn't one.
    ///
    /// A `.p8` is a few lines of text, and line breaks are the first
    /// thing a paste destroys — a single-line field removes them all.
    /// The content between the markers is base64, which survives that,
    /// so the key is recovered from it and laid out again properly.
    static func normalisedPrivateKey(_ raw: String) -> String? {
        var body = raw
        for marker in [
            "-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----",
            "-----BEGIN EC PRIVATE KEY-----", "-----END EC PRIVATE KEY-----",
        ] {
            body = body.replacingOccurrences(of: marker, with: "")
        }
        body = String(body.filter { !$0.isWhitespace })
        // A pasted "\n" typed out literally, as some notes apps do.
        body = body.replacingOccurrences(of: "\\n", with: "")

        guard body.count >= 100,
              body.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=") }),
              let decoded = Data(base64Encoded: body),
              // Every DER structure starts with a SEQUENCE tag.
              decoded.first == 0x30
        else { return nil }

        var lines: [String] = ["-----BEGIN PRIVATE KEY-----"]
        var rest = Substring(body)
        while !rest.isEmpty {
            lines.append(String(rest.prefix(64)))
            rest = rest.dropFirst(64)
        }
        lines.append("-----END PRIVATE KEY-----")
        return lines.joined(separator: "\n")
    }

    static func privateKey(_ raw: String) -> Verdict {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .invalid("Choose the .p8 file Apple gave you, or paste what's inside it.") }
        if text.contains("BEGIN CERTIFICATE") {
            return .invalid("That's a certificate, not the API key. You need the .p8 file from App Store Connect → Users and Access → Integrations.")
        }
        if text.contains("BEGIN RSA PRIVATE KEY") || text.contains("BEGIN OPENSSH") {
            return .invalid("That's a different kind of key. You need the .p8 file downloaded from App Store Connect.")
        }
        if normalisedPrivateKey(text) == nil {
            return .invalid("That doesn't look like the contents of a .p8 file. It should start with -----BEGIN PRIVATE KEY-----. Open the file and copy everything in it.")
        }
        return .ok
    }
}
