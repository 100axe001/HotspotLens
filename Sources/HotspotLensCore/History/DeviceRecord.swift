import Foundation
import GRDB

/// Persisted history row for one MAC address. For locally-administered
/// (randomized) MACs, `isRandomizedMAC` is `true` and callers (UI, this
/// store's own documentation) must not present this row as tracking a
/// single physical device across networks/reconnects -- the address itself
/// doesn't support that claim. See `AddressIdentity`.
public struct DeviceRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    public static let databaseTableName = "device_record"

    public var id: Int64?
    public var mac: String
    public var vendor: String?
    public var isRandomizedMAC: Bool
    public var label: String?
    public var firstSeen: Date
    public var lastSeen: Date
    public var connectionCount: Int
    public var isBlocked: Bool
    public var lastKnownIPv4: String?

    public init(
        id: Int64? = nil,
        mac: String,
        vendor: String?,
        isRandomizedMAC: Bool,
        label: String? = nil,
        firstSeen: Date,
        lastSeen: Date,
        connectionCount: Int,
        isBlocked: Bool = false,
        lastKnownIPv4: String? = nil
    ) {
        self.id = id
        self.mac = mac
        self.vendor = vendor
        self.isRandomizedMAC = isRandomizedMAC
        self.label = label
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.connectionCount = connectionCount
        self.isBlocked = isBlocked
        self.lastKnownIPv4 = lastKnownIPv4
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// What to show as the primary line in the UI: user label wins, then
    /// vendor, then the honest "can't identify" fallback.
    public var displayName: String {
        if let label, !label.isEmpty { return label }
        if isRandomizedMAC { return "Private/Randomized Address" }
        return vendor ?? "Unknown device"
    }
}

extension DeviceRecord {
    enum Columns {
        static let mac = Column("mac")
        static let lastSeen = Column("lastSeen")
        static let isBlocked = Column("isBlocked")
    }
}
