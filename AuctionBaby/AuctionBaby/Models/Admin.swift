import Foundation
import CryptoKit

/// God-mode credentials. Validates against a precomputed HMAC commitment
/// baked into the binary, so the plaintext password never appears anywhere —
/// not in git, not in the IPA.
///
/// Deliberately NOT seeded from the first password typed: on a fresh App
/// Store install that would hand god mode (roster edits, Stripe-touching
/// Worker calls) to whoever guesses the username first.
///
/// The salt + hash are shared with the AI Marketplace admin gate on purpose:
/// one owner, one password, both apps. Rotate by recomputing
/// HMAC-SHA256(salt, newPassword) with any HMAC tool and replacing the hash.
enum Admin {

    /// Validates admin credentials against the baked commitment.
    static func validate(username: String, password: String) -> Bool {
        let normalizedUser = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard normalizedUser == expectedUsername else { return false }
        return verify(password, against: expectedHash)
    }

    // MARK: - Private

    private static let expectedUsername = "valasek"

    /// HMAC-SHA256(salt, password), base64. The plaintext lives only with
    /// the owner.
    private static let expectedHash = "WHqrpIN4i7Xfmi5gwpca1L1LIPYlGohZK60qD6EdCjg="

    /// Derives a verification hash using HMAC-SHA256 with a fixed salt.
    /// This is NOT bcrypt — it's a simple commitment for a local-only gate.
    /// Server-side auth would use a proper KDF.
    private static func hashPassword(_ password: String) -> String {
        let salt = "AIMarketplace-Admin-2026"
        let key = SymmetricKey(data: Data(salt.utf8))
        let hmac = HMAC<SHA256>.authenticationCode(for: Data(password.utf8), using: key)
        return Data(hmac).base64EncodedString()
    }

    private static func verify(_ password: String, against hash: String) -> Bool {
        hashPassword(password) == hash
    }
}
