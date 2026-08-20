import XCTest
@testable import HotspotLensCore

final class NDPTableReaderTests: XCTestCase {
    func testParsesSampleOutputScopedToBridge() {
        let entries = NDPTableReader.parse(FixtureLoader.text("ndp_sample.txt"), bridgeInterface: "bridge100")

        // Header dropped, bridge100 permanent entry kept, bridge100 valid
        // entry kept, incomplete entry dropped, en0 entry dropped (wrong
        // interface).
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains { $0.mac.description == "a4:83:e7:12:34:56" })
        XCTAssertTrue(entries.contains { $0.mac.description == "3c:15:c2:aa:bb:cc" })
        XCTAssertFalse(entries.contains { $0.mac.description == "11:22:33:44:55:66" })
    }

    func testScopeSuffixIsStripped() {
        let entries = NDPTableReader.parse(FixtureLoader.text("ndp_sample.txt"), bridgeInterface: "bridge100")
        let scoped = entries.first { $0.mac.description == "a4:83:e7:12:34:56" }
        XCTAssertEqual(scoped?.ipv6, "fe80::aa83:e7ff:fe12:3456")
    }

    func testEmptyOutputProducesNoEntries() {
        XCTAssertTrue(NDPTableReader.parse("", bridgeInterface: "bridge100").isEmpty)
    }
}
