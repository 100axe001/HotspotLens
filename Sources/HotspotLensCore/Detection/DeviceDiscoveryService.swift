import Foundation

/// The result of a single discovery pass.
public struct DiscoverySnapshot: Sendable {
    public let hotspotState: HotspotState
    public let devices: [Device]
    public let takenAt: Date
    /// Non-fatal problems hit while assembling this snapshot (e.g. the
    /// lease file was present but partially malformed). Discovery still
    /// produces a best-effort device list rather than failing outright --
    /// see README Known Limitations.
    public let warnings: [String]
}

/// Merges ARP (IPv4), NDP (IPv6), and DHCP lease data into one deduplicated
/// device list, keyed by MAC address. This is the only place in the app
/// that decides "is this the same device" -- and it deliberately does NOT
/// try to correlate two different locally-administered MACs as the same
/// physical device across sightings, because that would fabricate an
/// identity the data doesn't support.
public struct DeviceDiscoveryService: Sendable {
    private let arpReader: ARPTableReader
    private let ndpReader: NDPTableReader
    private let leaseReader: DHCPLeaseReader
    private let hotspotMonitor: HotspotMonitor
    private let vendorLookup: VendorLookupService?
    private let checkReachability: Bool

    public init(
        arpReader: ARPTableReader = ARPTableReader(),
        ndpReader: NDPTableReader = NDPTableReader(),
        leaseReader: DHCPLeaseReader = DHCPLeaseReader(),
        hotspotMonitor: HotspotMonitor = HotspotMonitor(),
        vendorLookup: VendorLookupService? = try? VendorLookupService(),
        checkReachability: Bool = true
    ) {
        self.arpReader = arpReader
        self.ndpReader = ndpReader
        self.leaseReader = leaseReader
        self.hotspotMonitor = hotspotMonitor
        self.vendorLookup = vendorLookup
        self.checkReachability = checkReachability
    }

    public func discover() -> DiscoverySnapshot {
        let hotspotState = hotspotMonitor.currentState()
        var warnings: [String] = []

        // If sharing is definitively off, there is nothing to bridge-scan;
        // report zero devices rather than running commands whose output
        // would be meaningless (e.g. a stale bridge100 from a previous
        // session).
        guard case .active = hotspotState else {
            return DiscoverySnapshot(hotspotState: hotspotState, devices: [], takenAt: Date(), warnings: warnings)
        }

        var arpEntries: [ARPEntry] = []
        do {
            let allArp = try arpReader.readEntries()
            if case .active(let iface) = hotspotState {
                arpEntries = allArp.filter { $0.interface == iface }
            } else {
                arpEntries = allArp
            }
        } catch {
            warnings.append("Could not read ARP table: \(error)")
        }

        var ndpEntries: [NDPEntry] = []
        do {
            ndpEntries = try ndpReader.readEntries()
        } catch {
            warnings.append("Could not read IPv6 neighbor table: \(error)")
        }

        var leases: [DHCPLease] = []
        do {
            leases = try leaseReader.readLeases()
        } catch {
            warnings.append("Could not read DHCP lease file: \(error)")
        }

        let now = Date()
        var byMAC: [MACAddress: Device] = [:]

        for entry in arpEntries {
            var device = byMAC[entry.mac] ?? makeDevice(mac: entry.mac, sources: [], lastSeen: now)
            device.ipv4 = entry.ipv4
            device.sources.insert(.arp)
            device.lastSeen = now
            byMAC[entry.mac] = device
        }

        for entry in ndpEntries {
            var device = byMAC[entry.mac] ?? makeDevice(mac: entry.mac, sources: [], lastSeen: now)
            device.ipv6Addresses.insert(entry.ipv6)
            device.sources.insert(.ndp)
            device.lastSeen = now
            byMAC[entry.mac] = device
        }

        for lease in leases {
            var device = byMAC[lease.mac] ?? makeDevice(mac: lease.mac, sources: [], lastSeen: now)
            if device.ipv4 == nil {
                device.ipv4 = lease.ipv4
            }
            device.dhcpHostname = lease.hostname
            device.sources.insert(.dhcpLease)
            byMAC[lease.mac] = device
        }

        // Only surface devices actively connected right now (excluding the host gateway)
        let liveDevices = byMAC.values.filter { device in
            let isSelfGateway = device.ipv4 == "192.168.2.1" || device.mac.description == "00:00:00:00:00:00"
            guard !isSelfGateway else { return false }

            let hasLiveSource = device.sources.contains(.arp) || device.sources.contains(.ndp)
            guard hasLiveSource else { return false }

            if checkReachability, let ip = device.ipv4 {
                return self.isIPReachable(ip)
            }
            return true
        }

        return DiscoverySnapshot(
            hotspotState: hotspotState,
            devices: liveDevices.sorted { $0.mac.description < $1.mac.description },
            takenAt: now,
            warnings: warnings
        )
    }

    private func isIPReachable(_ ip: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", "250", ip]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func makeDevice(mac: MACAddress, sources: DeviceSources, lastSeen: Date) -> Device {
        let identity: AddressIdentity
        if mac.isLocallyAdministered {
            identity = .randomized
        } else {
            identity = .vendorAssigned(vendor: vendorLookup?.vendor(for: mac))
        }
        return Device(mac: mac, identity: identity, sources: sources, lastSeen: lastSeen)
    }
}
