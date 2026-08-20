import XCTest
@testable import HotspotLensCore

final class DHCPLeaseReaderTests: XCTestCase {
    func testParsesSampleLeases() {
        let leases = DHCPLeaseReader.parse(FixtureLoader.text("dhcp_leases_sample.txt"))
        XCTAssertEqual(leases.count, 3)

        let iphone = leases.first { $0.ipv4 == "192.168.2.3" }
        XCTAssertEqual(iphone?.mac.description, "a4:83:e7:12:34:56")
        XCTAssertEqual(iphone?.hostname, "Alexs-iPhone")
        XCTAssertNotNil(iphone?.leaseExpiry)

        let noName = leases.first { $0.ipv4 == "192.168.2.20" }
        XCTAssertNil(noName?.hostname)
    }

    func testMalformedBlocksAreSkippedIndividually() {
        let leases = DHCPLeaseReader.parse(FixtureLoader.text("dhcp_leases_malformed.txt"))
        // Only the first block (has both ip_address and hw_address) survives.
        XCTAssertEqual(leases.count, 1)
        XCTAssertEqual(leases.first?.hostname, "Good-Entry")
    }

    func testEmptyContentsProducesNoLeases() {
        XCTAssertTrue(DHCPLeaseReader.parse("").isEmpty)
    }

    func testMissingFileReturnsEmptyNotError() throws {
        let reader = DHCPLeaseReader(candidatePaths: ["/nonexistent/path/dhcpd_leases"]) { path in
            throw CocoaError(.fileReadNoSuchFile)
        }
        let leases = try reader.readLeases()
        XCTAssertTrue(leases.isEmpty)
    }

    func testFallsBackToSecondCandidatePath() throws {
        let reader = DHCPLeaseReader(candidatePaths: ["/first/missing", "/second/present"]) { path in
            guard path == "/second/present" else { throw CocoaError(.fileReadNoSuchFile) }
            return FixtureLoader.text("dhcp_leases_sample.txt")
        }
        let leases = try reader.readLeases()
        XCTAssertEqual(leases.count, 3)
    }
}
