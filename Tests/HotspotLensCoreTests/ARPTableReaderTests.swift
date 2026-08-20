import XCTest
@testable import HotspotLensCore

final class ARPTableReaderTests: XCTestCase {
    func testParsesSampleOutput() {
        let entries = ARPTableReader.parse(FixtureLoader.text("arp_sample.txt"))

        // 6 lines in fixture: one all-zero (kept), one valid, one incomplete
        // (dropped), one valid, one locally-administered valid, one
        // broadcast/multicast (dropped).
        XCTAssertEqual(entries.count, 4)

        XCTAssertTrue(entries.contains { $0.ipv4 == "192.168.2.3" && $0.mac.description == "a4:83:e7:12:34:56" })
        XCTAssertTrue(entries.contains { $0.ipv4 == "192.168.2.5" && $0.mac.description == "3c:15:c2:aa:bb:cc" })
        XCTAssertFalse(entries.contains { $0.ipv4 == "192.168.2.4" })
        XCTAssertFalse(entries.contains { $0.ipv4 == "192.168.2.255" })
    }

    func testEmptyOutputProducesNoEntries() {
        let entries = ARPTableReader.parse(FixtureLoader.text("arp_empty.txt"))
        XCTAssertTrue(entries.isEmpty)
    }

    func testMalformedLinesAreSkippedIndividually() {
        let entries = ARPTableReader.parse(FixtureLoader.text("arp_malformed.txt"))
        // Only the last line (valid IP + valid MAC) should survive.
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.ipv4, "192.168.2.11")
    }

    func testReadEntriesSurfacesShellFailureAsDetectionError() {
        let shell = FixtureShellRunner()
        shell.stub("/usr/sbin/arp", nonZeroExit: 1, stderr: "arp: permission denied")
        let reader = ARPTableReader(shell: shell)

        XCTAssertThrowsError(try reader.readEntries()) { error in
            guard case DetectionError.commandFailed(let tool, _) = error else {
                return XCTFail("Expected DetectionError.commandFailed, got \(error)")
            }
            XCTAssertEqual(tool, "arp")
        }
    }
}
