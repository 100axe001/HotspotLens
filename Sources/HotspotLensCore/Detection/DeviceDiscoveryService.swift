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

    public init(
        arpReader: ARPTableReader = ARPTableReader(),
        ndpReader: NDPTableReader = NDPTableReader(),
        leaseReader: DHCPLeaseReader = DHCPLeaseReader(),
        hotspotMonitor: HotspotMonitor = HotspotMonitor(),
        vendorLookup: VendorLookupService? = try? VendorLookupService()
    ) {
        self.arpReader = arpReader
        self.ndpReader = ndpReader
        self.leaseReader = leaseReader
        self.hotspotMonitor = hotspotMonitor
        self.vendorLookup = vendorLookup
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
                let filtered = allArp.filter { $0.interface == iface }
                // Fallback to all entries if interface matching yields empty list
                arpEntries = filtered.isEmpty ? allArp : filtered
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
            // A lease file entry alone doesn't prove the device is *currently*
            // connected (leases outlive a session); only fill the IP if ARP
            // didn't already give us a fresher one, but always record the
            // hostname since that's harmless, useful metadata regardless of
            // liveness.
            if device.ipv4 == nil {
                device.ipv4 = lease.ipv4
            }
            device.dhcpHostname = lease.hostname
            device.sources.insert(.dhcpLease)
            byMAC[lease.mac] = device
        }

        // A device that only appears via a DHCP lease (no ARP/NDP entry) is
        // not currently on the bridge -- it's a past lease. Only surface
        // devices with live-signal evidence (ARP or NDP), excluding the host gateway itself.
        let liveDevices = byMAC.values.filter { device in
            let isLive = device.sources.contains(.arp) || device.sources.contains(.ndp)
            let isSelfGateway = device.ipv4 == "192.168.2.1" || device.mac.description == "00:00:00:00:00:00"
            return isLive && !isSelfGateway
        }

        return DiscoverySnapshot(
            hotspotState: hotspotState,
            devices: liveDevices.sorted { $0.mac.description < $1.mac.description },
            takenAt: now,
            warnings: warnings
        )
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
