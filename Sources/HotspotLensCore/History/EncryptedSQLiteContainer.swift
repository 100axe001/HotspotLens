import Foundation
import CryptoKit

/// Keeps the on-disk history database encrypted at rest without requiring a
/// SQLCipher-linked SQLite build (see README "Tech Stack" for why: plain
/// GRDB via Swift Package Manager links Apple's system SQLite, which
/// SQLCipher cannot transparently replace without vendoring/forking GRDB's
/// own C target -- judged out of scope for a from-scratch build we can't
/// compile-verify here).
///
/// Design: GRDB operates on an ordinary, unencrypted SQLite file in a
/// private temporary working directory. Whenever the store performs a
/// mutation, it asks this container to `flush()`, which AES-256-GCM
/// encrypts the *entire* working file and atomically replaces the resting
/// ciphertext in Application Support. On open, the ciphertext (if any) is
/// decrypted into a fresh working file.
///
/// Honest limitation vs. real SQLCipher: SQLCipher encrypts every page as
/// it's written, so there is never a plaintext copy on disk. Here, a
/// plaintext working copy exists on disk *while the app is running*,
/// readable by anyone with access to the running user session (the same
/// threat model as most local app data). It is deleted (best-effort
/// overwrite-then-remove) on clean shutdown. This protects data at rest
/// when the Mac is off or the app isn't running, and against someone
/// copying files off the disk/backup without the Keychain key -- it does
/// not protect against an attacker with live access to the logged-in
/// session while HotspotLens is running, which page-level SQLCipher
/// encryption wouldn't meaningfully protect against on a single-user Mac
/// either. See README Known Limitations.
public final class EncryptedSQLiteContainer: @unchecked Sendable {
    public let workingFileURL: URL
    private let restFileURL: URL
    private let key: SymmetricKey
    private let lock = NSLock()

    public enum ContainerError: Error, Sendable {
        case decryptionFailed
    }

    public init(restFileURL: URL, key: SymmetricKey, workingDirectory: URL = FileManager.default.temporaryDirectory) throws {
        self.restFileURL = restFileURL
        self.key = key
        self.workingFileURL = workingDirectory.appendingPathComponent("com.hotspotlens.history-\(UUID().uuidString).sqlite")

        try FileManager.default.createDirectory(
            at: restFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: restFileURL.path) {
            try Self.decrypt(from: restFileURL, to: workingFileURL, key: key)
        } else {
            FileManager.default.createFile(atPath: workingFileURL.path, contents: nil)
        }
    }

    /// Encrypts the current working file and atomically replaces the
    /// resting ciphertext. Call after every mutation that must survive a
    /// crash/quit, and from app-lifecycle hooks (resign active, terminate).
    public func flush() throws {
        lock.lock()
        defer { lock.unlock() }
        let plaintext = try Data(contentsOf: workingFileURL)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw ContainerError.decryptionFailed
        }
        let tempURL = restFileURL.appendingPathExtension("tmp-\(UUID().uuidString)")
        try combined.write(to: tempURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(restFileURL, withItemAt: tempURL)
    }

    /// Best-effort secure cleanup of the plaintext working copy. Call on
    /// clean shutdown after a final `flush()`.
    public func destroyWorkingCopy() {
        guard let handle = try? FileHandle(forWritingTo: workingFileURL) else {
            try? FileManager.default.removeItem(at: workingFileURL)
            return
        }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)
        try? handle.write(contentsOf: Data(count: Int(size)))
        try? handle.close()
        try? FileManager.default.removeItem(at: workingFileURL)
    }

    private static func decrypt(from restURL: URL, to workingURL: URL, key: SymmetricKey) throws {
        let combined = try Data(contentsOf: restURL)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        try plaintext.write(to: workingURL, options: .atomic)
    }
}
