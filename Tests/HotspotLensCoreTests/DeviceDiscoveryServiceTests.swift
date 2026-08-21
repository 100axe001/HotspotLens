import XCTest
@testable import HotspotLensCore

final class DeviceDiscoveryServiceTests: XCTestCase {
    private func makeService(
        ifconfigUp: Bool,
        arpOutput: String = "",
        ndpOutput: String = "",
        leaseContents: String? = nil
    ) -> DeviceDiscoveryService {
        let shell = FixtureShellRunner()
        if ifconfigUp {
            shell.stub("/sbin/ifconfig", output: "bridge100: flags=8a63<UP,BROADCAST,SMART,RUNNING> mtu 1500")
        } else {
            shell.stub("/sbin/ifconfig", nonZeroExit: 1, stderr: "interface does not exist")
        }
        shell.stub("/usr/sbin/arp", output: arpOutput)
        shell.stub("/usr/sbin/ndp", output: ndpOutput)

        let leaseReader = DHCPLeaseReader(candidatePaths: ["/var/db/dhcpd_leases"]) { _ in
            guard let leaseContents else { throw CocoaError(.fileReadNoSuchFile) }
            return leaseContents
        }

        return DeviceDiscoveryService(
            arpReader: ARPTableReader(shell: shell),
            ndpReader: NDPTableReader(shell: shell),
            leaseReader: leaseReader,
            hotspotMonitor: HotspotMonitor(shell: shell),
            vendorLookup: VendorLookupService(table: ["a4:83:e7": "Apple"]),
            checkReachability: false
        )
    }

    func testInactiveHotspotReturnsNoDevicesWithoutRunningReaders() {
        let service = makeService(ifconfigUp: false)
        let snapshot = service.discover()
        XCTAssertEqual(snapshot.hotspotState, .inactive)
        XCTAssertTrue(snapshot.devices.isEmpty)
    }

    func testMergesARPAndDHCPForSameDevice() {
        let arp = "? (192.168.2.3) at a4:83:e7:12:34:56 on bridge100 ifscope [ethernet]"
        let leases = """
        {
        \tip_address=192.168.2.3
        \thw_address=1,a4:83:e7:12:34:56
        \tname=Alexs-iPhone
        }
        """
        let service = makeService(ifconfigUp: true, arpOutput: arp, leaseContents: leases)
        let snapshot = service.discover()

        XCTAssertEqual(snapshot.devices.count, 1)
        let device = snapshot.devices[0]
        XCTAssertEqual(device.ipv4, "192.168.2.3")
        XCTAssertEqual(device.dhcpHostname, "Alexs-iPhone")
        XCTAssertEqual(device.defaultDisplayName, "Alexs-iPhone")
        XCTAssertTrue(device.sources.contains(.arp))
        XCTAssertTrue(device.sources.contains(.dhcpLease))
        if case .vendorAssigned(let vendor) = device.identity {
            XCTAssertEqual(vendor, "Apple")
        } else {
            XCTFail("Expected vendorAssigned identity")
        }
    }

    func testRandomizedMACIsLabeledNotGuessed() {
        // 8a has the U/L bit set.
        let arp = "? (192.168.2.6) at 8a:3f:19:00:11:22 on bridge100 ifscope [ethernet]"
        let service = makeService(ifconfigUp: true, arpOutput: arp)
        let snapshot = service.discover()

        XCTAssertEqual(snapshot.devices.count, 1)
        XCTAssertTrue(snapshot.devices[0].identity.isRandomized)
        XCTAssertEqual(snapshot.devices[0].defaultDisplayName, "Private/Randomized Address")
    }

    func testDHCPOnlyDeviceWithoutLiveARPOrNDPIsNotShownAsConnected() {
        let leases = """
        {
        \tip_address=192.168.2.3
        \thw_address=1,a4:83:e7:12:34:56
        \tname=Stale-Lease
        }
        """
        let service = makeService(ifconfigUp: true, leaseContents: leases)
        let snapshot = service.discover()
        XCTAssertTrue(snapshot.devices.isEmpty)
    }

    func testMergesIPv6FromNDP() {
        let ndp = """
        Neighbor                             Linklayer Address  Netif Expire    St Flgs Prbs
        fe80::1%bridge100                    a4:83:e7:12:34:56  bridge100 permanent R
        """
        let service = makeService(ifconfigUp: true, ndpOutput: ndp)
        let snapshot = service.discover()

        XCTAssertEqual(snapshot.devices.count, 1)
        XCTAssertTrue(snapshot.devices[0].ipv6Addresses.contains("fe80::1"))
        XCTAssertTrue(snapshot.devices[0].sources.contains(.ndp))
    }
}
