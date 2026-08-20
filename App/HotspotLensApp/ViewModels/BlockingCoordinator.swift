import Foundation
import HotspotLensCore

/// Ties together "which devices the user wants blocked" (persisted in
/// `DeviceHistoryStore`, keyed by MAC) with "which IPs actually have a pf
/// rule right now" (owned by the privileged helper, keyed by IP). Since
/// blocking is IP-based but a device's DHCP lease can change, this is also
/// what notices a blocked device came back under a new IP and reapplies the
/// rule -- without this, a blocked device's owner could reconnect and get a
/// fresh lease that quietly bypasses the old rule.
@MainActor
final class BlockingCoordinator: ObservableObject {
    @Published private(set) var blockedRecords: [DeviceRecord] = []
    @Published var lastError: String?

    private let store: DeviceHistoryStore?
    private let helper: PrivilegedHelperManager

    init(store: DeviceHistoryStore?, helper: PrivilegedHelperManager) {
        self.store = store
        self.helper = helper
    }

    func reload() async {
        guard let store else { return }
        do {
            blockedRecords = try await store.blockedRecords()
        } catch {
            lastError = "Couldn't load blocked devices: \(error)"
        }
    }

    /// Call after a confirmation dialog. `ipv4` is the device's IP right
    /// now (from the live discovery list if available, else the last known
    /// lease) -- see README for why this app blocks by IP, not MAC.
    func block(record: DeviceRecord, ipv4: String) async {
        guard let store, let id = record.id else { return }

        if helper.availability == .notRegistered {
            helper.register()
        }

        let result = await helper.blockIPv4(ipv4, mac: record.mac)
        switch result {
        case .success:
            do {
                try await store.setBlocked(recordID: id, blocked: true)
                await reload()
            } catch {
                lastError = "Block applied, but couldn't save that to history: \(error)"
            }
        case .failure(let error):
            lastError = error.userMessage
        }
    }

    func unblock(record: DeviceRecord) async {
        guard let store, let id = record.id, let ipv4 = record.lastKnownIPv4 else {
            lastError = "No known IP address to unblock for this device."
            return
        }

        let result = await helper.unblockIPv4(ipv4)
        switch result {
        case .success:
            do {
                try await store.setBlocked(recordID: id, blocked: false)
                await reload()
            } catch {
                lastError = "Unblock applied, but couldn't save that to history: \(error)"
            }
        case .failure(let error):
            lastError = error.userMessage
        }
    }

    /// Call whenever a fresh discovery snapshot arrives: if a blocked
    /// device shows up with a different IP than the one currently blocked,
    /// move the pf rule over so the block doesn't silently lapse.
    func reconcile(with liveDevices: [Device]) async {
        guard let store else { return }
        let liveByMAC = Dictionary(uniqueKeysWithValues: liveDevices.map { ($0.mac.description, $0) })

        for record in blockedRecords {
            guard let id = record.id else { continue }
            guard let live = liveByMAC[record.mac], let newIP = live.ipv4 else { continue }
            guard newIP != record.lastKnownIPv4 else { continue }

            let oldIP = record.lastKnownIPv4
            let blockResult = await helper.blockIPv4(newIP, mac: record.mac)
            guard case .success = blockResult else {
                lastError = "Couldn't move block rule to \(record.displayName)'s new address."
                continue
            }
            if let oldIP {
                _ = await helper.unblockIPv4(oldIP)
            }
            try? await store.setBlocked(recordID: id, blocked: true)
        }
        await reload()
    }
}
