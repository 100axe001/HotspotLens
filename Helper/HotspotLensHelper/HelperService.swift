import Foundation

/// Implements the XPC-exported protocol. One instance is created per
/// accepted connection (see `main.swift`); `PFRuleManager` and the audit
/// log are cheap to construct and internally serialize their own access,
/// so per-connection instantiation keeps this type stateless and simple.
final class HelperService: NSObject, HotspotLensHelperProtocol {
    private let pf = PFRuleManager()
    private let auditLog = AuditLog()

    func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func blockIPv4(_ ipv4: String, mac: String, reply: @escaping (Bool, String?) -> Void) {
        do {
            try pf.block(ipv4)
            auditLog.record(action: "block", ipv4: ipv4, mac: mac)
            reply(true, nil)
        } catch {
            reply(false, "\(error)")
        }
    }

    func unblockIPv4(_ ipv4: String, reply: @escaping (Bool, String?) -> Void) {
        do {
            try pf.unblock(ipv4)
            auditLog.record(action: "unblock", ipv4: ipv4, mac: nil)
            reply(true, nil)
        } catch {
            reply(false, "\(error)")
        }
    }

    func currentlyBlockedIPv4Addresses(reply: @escaping ([String]) -> Void) {
        reply(Array(pf.blockedAddresses()).sorted())
    }
}

/// Append-only, human-readable log of every block/unblock action the
/// helper has ever performed, independent of the app's own history UI.
/// This exists so blocking can never be silently hidden even from someone
/// auditing the Mac directly (`cat` the file) -- see README's "no stealth
/// mode" commitment.
final class AuditLog {
    private let fileURL = URL(fileURLWithPath: "/Library/Application Support/HotspotLensHelper/audit.log")
    private let queue = DispatchQueue(label: "com.hotspotlens.helper.auditlog")

    init() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func record(action: String, ipv4: String, mac: String?) {
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(timestamp)\t\(action)\tip=\(ipv4)\tmac=\(mac ?? "-")\n"
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: self.fileURL)
            }
        }
    }
}
