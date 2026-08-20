import Foundation

/// How an address family for a device was observed.
public enum IPAddress: Hashable, Sendable {
    case v4(String)
    case v6(String)

    public var stringValue: String {
        switch self {
        case .v4(let s), .v6(let s): return s
        }
    }

    public var isIPv6: Bool {
        if case .v6 = self { return true }
        return false
    }
}

/// Which system source contributed a sighting. Kept on the merged `Device`
/// so the UI/history layer can explain *why* a device is believed present
/// (useful when debugging "why did this vanish" -- see README Known
/// Limitations re: ARP cache expiry).
public struct DeviceSources: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let arp = DeviceSources(rawValue: 1 << 0)
    public static let ndp = DeviceSources(rawValue: 1 << 1)
    public static let dhcpLease = DeviceSources(rawValue: 1 << 2)
}

/// Identity confidence for a device record, driven entirely by whether its
/// MAC address is IEEE-assigned (stable) or locally administered
/// (randomized per network, not a stable identifier). This is surfaced
/// explicitly rather than silently merged so history/labels never claim a
/// false persistent identity.
public enum AddressIdentity: Sendable, Equatable, Hashable {
    /// OUI-assigned MAC; vendor lookup is meaningful and the MAC is a
    /// reasonable (not perfect -- MACs can still be spoofed) stable key.
    case vendorAssigned(vendor: String?)
    /// Locally-administered ("private"/randomized) MAC. Vendor is unknowable
    /// and the address should not be treated as a durable identity across
    /// sightings or reconnects.
    case randomized

    public var isRandomized: Bool {
        if case .randomized = self { return true }
        return false
    }

    public var displayVendor: String {
        switch self {
        case .vendorAssigned(let vendor): return vendor ?? "Unknown vendor"
        case .randomized: return "Private/Randomized Address"
        }
    }
}

/// A single, deduplicated device currently visible on the hotspot bridge,
/// merged from whichever of ARP / NDP / DHCP lease data mentioned it.
public struct Device: Identifiable, Hashable, Sendable {
    public var id: String { mac.description }

    public let mac: MACAddress
    public let identity: AddressIdentity
    public var ipv4: String?
    public var ipv6Addresses: Set<String>
    public var dhcpHostname: String?
    public var sources: DeviceSources
    public var lastSeen: Date

    public init(
        mac: MACAddress,
        identity: AddressIdentity,
        ipv4: String? = nil,
        ipv6Addresses: Set<String> = [],
        dhcpHostname: String? = nil,
        sources: DeviceSources,
        lastSeen: Date = Date()
    ) {
        self.mac = mac
        self.identity = identity
        self.ipv4 = ipv4
        self.ipv6Addresses = ipv6Addresses
        self.dhcpHostname = dhcpHostname
        self.sources = sources
        self.lastSeen = lastSeen
    }

    /// Best-effort human label when no user-defined label exists yet.
    public var defaultDisplayName: String {
        if let hostname = dhcpHostname, !hostname.isEmpty {
            return hostname
        }
        return identity.displayVendor
    }
}
