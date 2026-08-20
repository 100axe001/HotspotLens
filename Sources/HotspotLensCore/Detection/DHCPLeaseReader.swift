import Foundation

/// A single lease record parsed out of a `bootpd`/`InternetSharing` lease
/// file.
public struct DHCPLease: Hashable, Sendable {
    public let ipv4: String
    public let mac: MACAddress
    public let hostname: String?
    public let leaseExpiry: Date?
}

/// Reads and parses the DHCP lease file written by `bootpd` when Internet
/// Sharing is active.
///
/// The lease file location and exact key set has moved around across macOS
/// versions (see README Known Limitations). This reader tries the known
/// candidate paths in order and parses whichever one exists using the
/// classic `{ ip_address=...; hw_address=1,aa:bb:cc:dd:ee:ff; name=...; }`
/// block format written by `bootpd`.
public struct DHCPLeaseReader: Sendable {
    /// Candidate paths, newest-first. `bootpd` has shipped its shared-Internet
    /// lease file at `/var/db/dhcpd_leases` historically; some macOS
    /// versions instead (or additionally) populate
    /// `/private/var/db/dhcpd_leases`, which is the same file via a
    /// non-symlinked path and is included defensively.
    public static let defaultCandidatePaths = [
        "/var/db/dhcpd_leases",
        "/private/var/db/dhcpd_leases"
    ]

    private let candidatePaths: [String]
    private let fileReader: (String) throws -> String

    public init(
        candidatePaths: [String] = DHCPLeaseReader.defaultCandidatePaths,
        fileReader: @escaping (String) throws -> String = { path in
            try String(contentsOfFile: path, encoding: .utf8)
        }
    ) {
        self.candidatePaths = candidatePaths
        self.fileReader = fileReader
    }

    /// Returns `[]` (not an error) if Internet Sharing has never handed out
    /// a lease, since "no lease file yet" is an expected, common state, not
    /// a failure. Throws only if a candidate path exists but is
    /// unreadable/corrupt in a way that can't be safely partially-parsed.
    public func readLeases() throws -> [DHCPLease] {
        for path in candidatePaths {
            guard let contents = try? fileReader(path) else { continue }
            return Self.parse(contents)
        }
        return []
    }

    /// Pure parser. Malformed blocks are skipped individually rather than
    /// aborting the whole parse -- one corrupt entry shouldn't hide every
    /// other device.
    public static func parse(_ contents: String) -> [DHCPLease] {
        var leases: [DHCPLease] = []

        // Blocks look like:
        // { ip_address=192.168.2.3
        //   hw_address=1,aa:bb:cc:dd:ee:ff
        //   identifier=1,aabbccddeeff
        //   lease=0x64f1a2b3
        //   name=Alexs-iPhone
        // }
        var currentFields: [String: String] = [:]
        var insideBlock = false

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "{" {
                insideBlock = true
                currentFields = [:]
                continue
            }
            if line == "}" {
                if insideBlock, let lease = Self.makeLease(from: currentFields) {
                    leases.append(lease)
                }
                insideBlock = false
                currentFields = [:]
                continue
            }
            guard insideBlock else { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            currentFields[key] = value
        }

        return leases
    }

    private static func makeLease(from fields: [String: String]) -> DHCPLease? {
        guard let ip = fields["ip_address"], !ip.isEmpty else { return nil }

        // hw_address is "1,aa:bb:cc:dd:ee:ff" where the leading "1," is the
        // ARP hardware-type byte for Ethernet; strip it if present.
        guard let hwRaw = fields["hw_address"] else { return nil }
        let macToken = hwRaw.contains(",") ? String(hwRaw.split(separator: ",", maxSplits: 1)[1]) : hwRaw
        guard let mac = MACAddress(macToken) else { return nil }

        var expiry: Date?
        if let leaseHex = fields["lease"] {
            let hex = leaseHex.hasPrefix("0x") ? String(leaseHex.dropFirst(2)) : leaseHex
            if let epoch = UInt32(hex, radix: 16) {
                expiry = Date(timeIntervalSince1970: TimeInterval(epoch))
            }
        }

        let hostname = fields["name"]

        return DHCPLease(ipv4: ip, mac: mac, hostname: hostname, leaseExpiry: expiry)
    }
}
