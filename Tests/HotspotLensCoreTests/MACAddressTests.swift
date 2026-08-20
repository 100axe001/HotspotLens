import XCTest
@testable import HotspotLensCore

final class MACAddressTests: XCTestCase {
    func testParsesColonSeparated() {
        let mac = MACAddress("a4:83:e7:12:34:56")
        XCTAssertEqual(mac?.description, "a4:83:e7:12:34:56")
    }

    func testParsesDashSeparated() {
        let mac = MACAddress("A4-83-E7-12-34-56")
        XCTAssertEqual(mac?.description, "a4:83:e7:12:34:56")
    }

    func testRejectsWrongOctetCount() {
        XCTAssertNil(MACAddress("aa:bb:cc:dd:ee"))
        XCTAssertNil(MACAddress("aa:bb:cc:dd:ee:ff:00"))
    }

    func testRejectsNonHex() {
        XCTAssertNil(MACAddress("zz:bb:cc:dd:ee:ff"))
    }

    func testOUI() {
        let mac = MACAddress("a4:83:e7:12:34:56")!
        XCTAssertEqual(mac.organizationallyUniqueIdentifier, "a4:83:e7")
    }

    func testLocallyAdministeredBit() {
        // 0x02 has the U/L bit set -> locally administered.
        XCTAssertTrue(MACAddress("02:00:00:11:22:33")!.isLocallyAdministered)
        // 0xa4 = 1010_0100, bit 1 is 0 -> universally administered (real Apple OUI).
        XCTAssertFalse(MACAddress("a4:83:e7:12:34:56")!.isLocallyAdministered)
        // 0x8a = 1000_1010, bit 1 is 1 -> locally administered.
        XCTAssertTrue(MACAddress("8a:3f:19:00:11:22")!.isLocallyAdministered)
    }

    func testMulticastBit() {
        XCTAssertTrue(MACAddress("ff:ff:ff:ff:ff:ff")!.isMulticast)
        XCTAssertFalse(MACAddress("a4:83:e7:12:34:56")!.isMulticast)
    }
}
