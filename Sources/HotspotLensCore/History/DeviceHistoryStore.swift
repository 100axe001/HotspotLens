import Foundation
import GRDB
import CryptoKit

/// Local, encrypted-at-rest history of devices seen on the hotspot.
///
/// An `actor` so all database access is serialized without callers needing
/// their own locking -- GRDB's `DatabaseQueue` is thread-safe on its own,
/// but the encrypt-on-flush step around it needs the same serialization.
public actor DeviceHistoryStore {
    private let dbQueue: DatabaseQueue
    private let container: EncryptedSQLiteContainer

    public enum StoreError: Error, Sendable {
        case recordNotFound(Int64)
    }

    public init(
        restFileURL: URL = DeviceHistoryStore.defaultRestFileURL(),
        keyStore: KeychainKeyStore = KeychainKeyStore()
    ) throws {
        let key = try keyStore.loadOrCreateKey()
        do {
            try self.init(restFileURL: restFileURL, key: key)
        } catch {
            try? FileManager.default.removeItem(at: restFileURL)
            try self.init(restFileURL: restFileURL, key: key)
        }
    }

    /// Test/tooling entry point that bypasses the Keychain, taking the
    /// encryption key directly.
    public init(restFileURL: URL, key: SymmetricKey) throws {
        let container = try EncryptedSQLiteContainer(restFileURL: restFileURL, key: key)
        self.container = container

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        self.dbQueue = try DatabaseQueue(path: container.workingFileURL.path, configuration: config)

        try dbQueue.write { db in
            try db.create(table: DeviceRecord.databaseTableName, ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("mac", .text).notNull().unique()
                t.column("vendor", .text)
                t.column("isRandomizedMAC", .boolean).notNull()
                t.column("label", .text)
                t.column("firstSeen", .datetime).notNull()
                t.column("lastSeen", .datetime).notNull()
                t.column("connectionCount", .integer).notNull()
                t.column("isBlocked", .boolean).notNull().defaults(to: false)
                t.column("lastKnownIPv4", .text)
            }
        }
    }

    public static func defaultRestFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("HotspotLens", isDirectory: true)
            .appendingPathComponent("history.sqlite.enc")
    }

    /// Records that `device` was seen right now: creates a new row on first
    /// sighting, or bumps `lastSeen`/`connectionCount` on an existing one.
    /// Deliberately does *not* try to merge across different randomized
    /// MACs -- see module documentation on `DeviceRecord`.
    public func recordSighting(_ device: Device) throws {
        let now = Date()
        let vendorForStorage: String? = device.identity.isRandomized ? nil : device.identity.displayVendor

        try dbQueue.write { db in
            if var existing = try DeviceRecord.filter(DeviceRecord.Columns.mac == device.mac.description).fetchOne(db) {
                existing.lastSeen = now
                existing.connectionCount += 1
                if let vendorForStorage {
                    existing.vendor = vendorForStorage
                }
                if let ipv4 = device.ipv4 {
                    existing.lastKnownIPv4 = ipv4
                }
                try existing.update(db)
            } else {
                var record = DeviceRecord(
                    mac: device.mac.description,
                    vendor: vendorForStorage,
                    isRandomizedMAC: device.identity.isRandomized,
                    firstSeen: now,
                    lastSeen: now,
                    connectionCount: 1,
                    lastKnownIPv4: device.ipv4
                )
                try record.insert(db)
            }
        }
        try container.flush()
    }

    public func allRecords() throws -> [DeviceRecord] {
        try dbQueue.read { db in
            try DeviceRecord.order(DeviceRecord.Columns.lastSeen.desc).fetchAll(db)
        }
    }

    public func setLabel(recordID: Int64, label: String?) throws {
        try dbQueue.write { db in
            guard var record = try DeviceRecord.fetchOne(db, key: recordID) else {
                throw StoreError.recordNotFound(recordID)
            }
            record.label = (label?.isEmpty ?? true) ? nil : label
            try record.update(db)
        }
        try container.flush()
    }

    /// Persists the user's intent to block/unblock a MAC. This is the
    /// source of truth for "which devices should be blocked"; the actual
    /// `pf` rule (keyed by current IP, since that's what `pf` filters on)
    /// is applied separately by `BlockedDeviceCoordinator`, which reconciles
    /// this flag against `lastKnownIPv4` -- including reapplying the rule
    /// under a device's new IP if its lease changes while blocked.
    public func setBlocked(recordID: Int64, blocked: Bool) throws {
        try dbQueue.write { db in
            guard var record = try DeviceRecord.fetchOne(db, key: recordID) else {
                throw StoreError.recordNotFound(recordID)
            }
            record.isBlocked = blocked
            try record.update(db)
        }
        try container.flush()
    }

    public func blockedRecords() throws -> [DeviceRecord] {
        try dbQueue.read { db in
            try DeviceRecord.filter(DeviceRecord.Columns.isBlocked == true).fetchAll(db)
        }
    }

    public func deleteRecord(id: Int64) throws {
        _ = try dbQueue.write { db in
            try DeviceRecord.deleteOne(db, key: id)
        }
        try container.flush()
    }

    public func deleteAll() throws {
        _ = try dbQueue.write { db in
            try DeviceRecord.deleteAll(db)
        }
        try container.flush()
    }

    /// Call from app-lifecycle hooks (resign active / will terminate) as a
    /// safety net in addition to the per-mutation flush.
    public func flush() throws {
        try container.flush()
    }

    /// Call on clean shutdown, after a final `flush()`, to remove the
    /// plaintext working copy from the temporary directory.
    public func shutdown() {
        container.destroyWorkingCopy()
    }
}
