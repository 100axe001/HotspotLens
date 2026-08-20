import Foundation

/// A single row parsed out of `ndp -an` output -- the IPv6 analogue of the
/// ARP table, needed so dual-stack and IPv6-only clients aren't invisible
/// (see README Known Limitations for what this does *not* cover).
public struct NDPEntry: Hashable, Sendable {
    public let ipv6: String
    public let mac: MACAddress
    public let interface: String?
}

/// Reads and parses the IPv6 neighbor cache via `ndp -an`.
///
/// Expected macOS line shape (header line, then rows):
///   `Neighbor                             Linklayer Address  Netif Expire    St Flgs Prbs`
///   `fe80::1%bridge100                    aa:bb:cc:dd:ee:ff  bridge100 permanent R`
///   `fd12:3456::42                        (incomplete)       bridge100 expired   N`
/// Only rows scoped to `bridge100` (the Internet Sharing bridge) and with a
/// resolved link-layer address are kept; link-local scope suffixes
/// (`%bridge100`) are stripped from the address for display.
public struct NDPTableReader: Sendable {
    private let shell: ShellRunning
    private let bridgeInterface: String

    public init(shell: ShellRunning = ProcessShellRunner(), bridgeInterface: String = "bridge100") {
        self.shell = shell
        self.bridgeInterface = bridgeInterface
    }

    public func readEntries() throws -> [NDPEntry] {
        let output: String
        do {
            output = try shell.run("/usr/sbin/ndp", arguments: ["-an"])
        } catch {
            throw DetectionError.commandFailed(tool: "ndp", underlying: error)
        }
        return Self.parse(output, bridgeInterface: bridgeInterface)
    }

    public static func parse(_ output: String, bridgeInterface: String) -> [NDPEntry] {
        var entries: [NDPEntry] = []

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // Skip the header row.
            if line.hasPrefix("Neighbor") { continue }

            let columns = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard columns.count >= 3 else { continue }

            var ipv6 = columns[0]
            if let percentIndex = ipv6.firstIndex(of: "%") {
                ipv6 = String(ipv6[ipv6.startIndex..<percentIndex])
            }
            guard ipv6.contains(":") else { continue }

            let macToken = columns[1]
            guard macToken != "(incomplete)", let mac = MACAddress(macToken), !mac.isMulticast else {
                continue
            }

            let netif = columns.count >= 3 ? columns[2] : nil
            guard netif == bridgeInterface else { continue }

            entries.append(NDPEntry(ipv6: ipv6, mac: mac, interface: netif))
        }

        return entries
    }
}
