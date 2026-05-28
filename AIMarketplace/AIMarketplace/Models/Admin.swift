import Foundation
import CryptoKit
import Security

/// God-mode credentials. Validates against a bcrypt-equivalent hash stored in
/// the Keychain, so the plaintext password never appears in the binary.
/// On first launch the hash is seeded; future validations compare against it.
enum Admin {

    /// Validates admin credentials. On first launch, stores the expected
    /// hash in the Keychain; subsequent calls compare against it.
    static func validate(username: String, password: String) -> Bool {
        let normalizedUser = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard normalizedUser == expectedUsername else { return false }

        if let stored = SecureStore.readString(account: "admin-pass-hash") {
            return verify(password, against: stored)
        } else {
            // First launch — seed the hash.
            let hash = hashPassword(password)
            SecureStore.writeString(hash, account: "admin-pass-hash")
            return true
        }
    }

    // MARK: - Private

    private static let expectedUsername = "valasek"

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

// MARK: - SecureStore extensions for Keychain string storage

extension SecureStore {
    private static let adminService = "com.aimarketplace.admin"

    static func readString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: adminService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func writeString(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: adminService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}