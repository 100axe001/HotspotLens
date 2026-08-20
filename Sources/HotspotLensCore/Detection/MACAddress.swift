import Foundation

/// A parsed, normalized MAC address plus the derived facts we can honestly
/// know about it from the bytes alone.
public struct MACAddress: Hashable, Sendable, CustomStringConvertible {
    /// Six bytes, canonical order as reported by the OS.
    public let octets: [UInt8]

    public init?(_ raw: String) {
        // Accepts "aa:bb:cc:dd:ee:ff", "aa-bb-cc-dd-ee-ff", or bare hex,
        // case-insensitively. Rejects anything that isn't exactly 6 octets
        // of valid hex -- this is the boundary between "trust the OS" and
        // "don't propagate garbage into the rest of the app".
        let cleaned = raw.replacingOccurrences(of: "-", with: ":")
        let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6 else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(6)
        for part in parts {
            guard part.count >= 1, part.count <= 2, let byte = UInt8(part, radix: 16) else {
                return nil
            }
            bytes.append(byte)
        }
        self.octets = bytes
    }

    init(octets: [UInt8]) {
        precondition(octets.count == 6, "MACAddress requires exactly 6 octets")
        self.octets = octets
    }

    public var description: String {
        octets.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// The IEEE OUI (first three octets), used for vendor lookup.
    public var organizationallyUniqueIdentifier: String {
        octets.prefix(3).map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// True if the U/L (universal/local) bit -- bit 1 of the first octet --
    /// is set, meaning the address is locally administered rather than
    /// assigned by the IEEE to a hardware vendor. Modern iOS/macOS/Android
    /// devices set this bit by default for per-network private MAC
    /// addresses, which means the OUI carries no vendor information and the
    /// address itself is not a stable identifier for the physical device.
    ///
    /// Bit layout of octet 0: `xxxxxx1x` locally administered,
    /// `xxxxxx0x` universally administered (IEEE-assigned).
    public var isLocallyAdministered: Bool {
        (octets[0] & 0b0000_0010) != 0
    }

    /// True if the multicast bit (bit 0 of the first octet) is set. Real
    /// client NICs never report this as their source address; seeing it in
    /// ARP/NDP output indicates a malformed or non-unicast entry that
    /// should be dropped rather than shown as a device.
    public var isMulticast: Bool {
        (octets[0] & 0b0000_0001) != 0
    }
}
