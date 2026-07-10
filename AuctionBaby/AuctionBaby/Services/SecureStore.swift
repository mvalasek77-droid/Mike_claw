import Foundation
import CryptoKit
import Security

enum CryptoBox {
    enum CryptoError: Error { case sealFailed }

    static func seal<T: Encodable>(_ value: T, key: SymmetricKey) throws -> Data {
        let plaintext = try JSONEncoder().encode(value)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw CryptoError.sealFailed }
        return combined
    }

    static func open<T: Decodable>(_ type: T.Type, from data: Data, key: SymmetricKey) throws -> T {
        let box = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(box, using: key)
        return try JSONDecoder().decode(T.self, from: plaintext)
    }
}

enum SecureStore {
    private static let service = "com.valasek.auctionbaby.keys"
    private static let account = "master-encryption-key"

    static func loadOrCreateMasterKey() -> SymmetricKey {
        if let data = readKey() { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        writeKey(raw)
        return key
    }

    private static func readKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func writeKey(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}

struct EncryptedArchive {
    private let url: URL
    private let key: SymmetricKey

    init(filename: String = "state.aesgcm") {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? FileManager.default.temporaryDirectory
        url = base.appendingPathComponent(filename)
        key = SecureStore.loadOrCreateMasterKey()
    }

    func save<T: Encodable>(_ value: T) {
        do {
            let data = try CryptoBox.seal(value, key: key)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            #if DEBUG
            print("EncryptedArchive save failed: \(error)")
            #endif
        }
    }

    func load<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? CryptoBox.open(type, from: data, key: key)
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
