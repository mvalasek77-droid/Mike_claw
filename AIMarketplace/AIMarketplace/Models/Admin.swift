import Foundation
import CryptoKit

/// God-mode credentials. Validates against a precomputed HMAC commitment
/// baked into the binary, so the plaintext password never appears anywhere.
///
/// Deliberately NOT seeded from the first password typed: on a fresh App
/// Store install that would hand god mode (catalog edits, Stripe-touching
/// Worker calls) to whoever guesses the username first.
enum Admin {

    /// Validates admin credentials against the baked commitment.
    static func validate(username: String, password: String) -> Bool {
        let normalizedUser = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard normalizedUser == expectedUsername else { return false }
        return verify(password, against: expectedHash)
    }

    // MARK: - Private

    private static let expectedUsername = "valasek"

    /// HMAC-SHA256(salt, password), base64. Regenerate with any HMAC tool if
    /// the owner password rotates — the plaintext lives only with the owner.
    private static let expectedHash = "WHqrpIN4i7Xfmi5gwpca1L1LIPYlGohZK60qD6EdCjg="

    /// Derives a verification hash using SHA-256 with a fixed salt.
    /// This is NOT bcrypt — it's a simple HMAC-based commitment for a
    /// local-only prototype gate. Server-side auth would use proper bcrypt.
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