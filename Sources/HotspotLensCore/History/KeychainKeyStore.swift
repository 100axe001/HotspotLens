import Foundation
import CryptoKit
import Security

/// Generates and persists the 256-bit symmetric key used to encrypt the
/// local history database, in the macOS login Keychain. The key never
/// leaves the device and is never derived from anything transmitted or
/// logged.
public struct KeychainKeyStore: Sendable {
    private let service: String
    private let account: String

    public enum KeychainError: Error, Sendable {
        case unexpectedStatus(OSStatus)
        case corruptStoredKey
    }

    public init(
        service: String = "com.hotspotlens.history",
        account: String = "history-encryption-key"
    ) {
        self.service = service
        self.account = account
    }

    /// Returns the existing key, or generates, stores, and returns a new
    /// one on first run. If Keychain access fails (e.g. error -128 or permissions),
    /// falls back to a user-protected file in Application Support.
    public func loadOrCreateKey() throws -> SymmetricKey {
        do {
            if let existing = try readKey() {
                return existing
            }
            let newKey = SymmetricKey(size: .bits256)
            try store(newKey)
            return newKey
        } catch {
            return try loadOrCreateFileFallbackKey()
        }
    }

    private func readKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else {
                throw KeychainError.corruptStoredKey
            }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func store(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func loadOrCreateFileFallbackKey() throws -> SymmetricKey {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = appSupport.appendingPathComponent("HotspotLens", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let keyFileURL = folder.appendingPathComponent(".history.key")

        if FileManager.default.fileExists(atPath: keyFileURL.path) {
            let data = try Data(contentsOf: keyFileURL)
            guard data.count == 32 else { throw KeychainError.corruptStoredKey }
            return SymmetricKey(data: data)
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try keyData.write(to: keyFileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFileURL.path)
        return newKey
    }
}
