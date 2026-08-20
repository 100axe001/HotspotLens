import Foundation

/// A single row parsed out of `arp -a -n` output.
public struct ARPEntry: Hashable, Sendable {
    public let ipv4: String
    public let mac: MACAddress
    public let interface: String?
}

/// Reads and parses the IPv4 neighbor table via `arp -a -n`.
///
/// Expected macOS line shape:
///   `? (192.168.2.3) at aa:bb:cc:dd:ee:ff on bridge100 ifscope [ethernet]`
/// Incomplete entries look like:
///   `? (192.168.2.4) at (incomplete) on bridge100 ifscope [ethernet]`
/// and are skipped -- an incomplete entry means the kernel hasn't resolved
/// the MAC yet, so there is nothing honest to report for that row.
public struct ARPTableReader: Sendable {
    private let shell: ShellRunning

    public init(shell: ShellRunning = ProcessShellRunner()) {
        self.shell = shell
    }

    public func readEntries() throws -> [ARPEntry] {
        let output: String
        do {
            output = try shell.run("/usr/sbin/arp", arguments: ["-a", "-n"])
        } catch {
            throw DetectionError.commandFailed(tool: "arp", underlying: error)
        }
        return Self.parse(output)
    }

    /// Pure parser, exposed `static` so tests can feed it fixture text
    /// without touching the real system.
    public static func parse(_ output: String) -> [ARPEntry] {
        var entries: [ARPEntry] = []

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Pull the IP out of the parenthesized group.
            guard
                let ipOpen = line.firstIndex(of: "("),
                let ipClose = line.firstIndex(of: ")"),
                ipOpen < ipClose
            else { continue }
            let ip = String(line[line.index(after: ipOpen)..<ipClose])
            guard Self.looksLikeIPv4(ip) else { continue }

            guard let atRange = line.range(of: " at ") else { continue }
            let afterAt = line[atRange.upperBound...]
            let macToken = afterAt.split(separator: " ").first.map(String.init) ?? ""

            if macToken == "(incomplete)" {
                continue
            }
            guard let mac = MACAddress(macToken), !mac.isMulticast else { continue }

            var interface: String?
            if let onRange = line.range(of: " on ") {
                let afterOn = line[onRange.upperBound...]
                interface = afterOn.split(separator: " ").first.map(String.init)
            }

            entries.append(ARPEntry(ipv4: ip, mac: mac, interface: interface))
        }

        return entries
    }

    private static func looksLikeIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part) else { return false }
            return (0...255).contains(value)
        }
    }
}

public enum DetectionError: Error, Sendable {
    case commandFailed(tool: String, underlying: Error)
    case interfaceAbsent(name: String)
    case fileUnreadable(path: String, underlying: Error?)
    case fileMissing(path: String)
}
