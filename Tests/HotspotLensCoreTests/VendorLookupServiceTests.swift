import XCTest
@testable import HotspotLensCore

final class VendorLookupServiceTests: XCTestCase {
    let service = VendorLookupService(table: [
        "a4:83:e7": "Apple",
        "24:0a:c4": "Espressif"
    ])

    func testKnownOUIReturnsVendor() {
        XCTAssertEqual(service.vendor(for: MACAddress("a4:83:e7:12:34:56")!), "Apple")
    }

    func testUnknownOUIReturnsNil() {
        XCTAssertNil(service.vendor(for: MACAddress("11:22:33:44:55:66")!))
    }

    func testLocallyAdministeredNeverReturnsVendorEvenIfOUIMatchesByCoincidence() {
        // 0x02 has the U/L bit set, so this must never resolve to a vendor
        // even though we could in principle look up its OUI bytes.
        XCTAssertNil(service.vendor(for: MACAddress("02:0a:c4:11:22:33")!))
    }

    func testBundledResourceLoadsAndDecodes() throws {
        let bundled = try VendorLookupService()
        XCTAssertGreaterThan(bundled.entryCount, 0)
        XCTAssertEqual(bundled.vendor(for: MACAddress("a4:83:e7:12:34:56")!), "Apple")
    }
}
