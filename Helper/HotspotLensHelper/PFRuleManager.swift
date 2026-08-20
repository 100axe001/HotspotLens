import Foundation
import HotspotLensCore

/// Manages a dedicated, named `pf` anchor (`com.hotspotlens`) that blocks
/// specific IPv4 addresses on the hotspot bridge. Runs only inside the
/// privileged helper daemon, which is root; the main GUI app never touches
/// `pfctl` directly.
///
/// Why a named anchor loaded via `pfctl -a <name> -f <file>` instead of
/// editing `/etc/pf.conf`: it's the least invasive option available --
/// system `pf.conf` (and whatever VPN/firewall/parental-control software
/// already manages it) is left untouched, and our rules live in their own
/// file we fully own. The tradeoff, documented in the README, is that this
/// depends on pf being enabled and no other tool tearing down anchors
/// wholesale; HotspotLens never disables pf globally (only enables it if
/// it finds it off) and never touches anchors other than its own.
final class PFRuleManager {
    private let anchorName = "com.apple/hotspotlens"
    private let rulesFileURL = URL(fileURLWithPath: "/etc/pf.anchors/com.hotspotlens.rules")
    private let stateFileURL = URL(fileURLWithPath: "/Library/Application Support/HotspotLensHelper/blocked_ips.json")
    private let shell: ShellRunning
    private let queue = DispatchQueue(label: "com.hotspotlens.helper.pfrules")

    enum PFError: Error, CustomStringConvertible {
        case pfctlFailed(String)
        case invalidAddress(String)

        var description: String {
            switch self {
            case .pfctlFailed(let detail): return "pfctl failed: \(detail)"
            case .invalidAddress(let addr): return "Not a valid IPv4 address: \(addr)"
            }
        }
    }

    init(shell: ShellRunning = ProcessShellRunner()) {
        self.shell = shell
        try? FileManager.default.createDirectory(
            at: stateFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func blockedAddresses() -> Set<String> {
        queue.sync { loadState() }
    }

    func block(_ ipv4: String) throws {
        guard Self.isValidIPv4(ipv4) else { throw PFError.invalidAddress(ipv4) }
        try queue.sync {
            var state = loadState()
            state.insert(ipv4)
            try apply(state)
        }
    }

    func unblock(_ ipv4: String) throws {
        try queue.sync {
            var state = loadState()
            state.remove(ipv4)
            try apply(state)
        }
    }

    // MARK: - pf plumbing

    private func apply(_ addresses: Set<String>) throws {
        try ensurePFEnabled()

        let rules = addresses.sorted().flatMap { ip in
            [
                "block drop quick from \(ip) to any",
                "block drop quick from any to \(ip)"
            ]
        }.joined(separator: "\n") + "\n"

        try rules.write(to: rulesFileURL, atomically: true, encoding: .utf8)

        do {
            _ = try shell.run("/sbin/pfctl", arguments: ["-a", anchorName, "-f", rulesFileURL.path])
        } catch {
            throw PFError.pfctlFailed("\(error)")
        }

        try saveState(addresses)
    }

    private func ensurePFEnabled() throws {
        // `pfctl -s info` reports "Status: Enabled" / "Status: Disabled".
        // Only flip it on if it's off; never turn it off ourselves, since pf
        // may be owned/managed by other software the user relies on.
        let status = (try? shell.run("/sbin/pfctl", arguments: ["-s", "info"])) ?? ""
        guard status.contains("Status: Enabled") else {
            _ = try? shell.run("/sbin/pfctl", arguments: ["-E"])
            return
        }
    }

    private func loadState() -> Set<String> {
        guard
            let data = try? Data(contentsOf: stateFileURL),
            let list = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return Set(list)
    }

    private func saveState(_ addresses: Set<String>) throws {
        let data = try JSONEncoder().encode(addresses.sorted())
        try data.write(to: stateFileURL, options: .atomic)
    }

    static func isValidIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), String(value) == part else { return false }
            return (0...255).contains(value)
        }
    }
}
