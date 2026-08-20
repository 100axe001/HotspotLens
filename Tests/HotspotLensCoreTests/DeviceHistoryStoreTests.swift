import XCTest
import CryptoKit
@testable import HotspotLensCore

final class DeviceHistoryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() throws -> DeviceHistoryStore {
        let restURL = tempDir.appendingPathComponent("history.sqlite.enc")
        let key = SymmetricKey(size: .bits256)
        return try DeviceHistoryStore(restFileURL: restURL, key: key)
    }

    private func makeDevice(mac: String, randomized: Bool) -> Device {
        let macAddr = MACAddress(mac)!
        let identity: AddressIdentity = randomized ? .randomized : .vendorAssigned(vendor: "Apple")
        return Device(mac: macAddr, identity: identity, sources: [.arp])
    }

    func testFirstSightingInsertsRecord() async throws {
        let store = try makeStore()
        try await store.recordSighting(makeDevice(mac: "a4:83:e7:12:34:56", randomized: false))

        let records = try await store.allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].connectionCount, 1)
        XCTAssertEqual(records[0].vendor, "Apple")
        XCTAssertFalse(records[0].isRandomizedMAC)
    }

    func testRepeatedSightingIncrementsCount() async throws {
        let store = try makeStore()
        let device = makeDevice(mac: "a4:83:e7:12:34:56", randomized: false)
        try await store.recordSighting(device)
        try await store.recordSighting(device)
        try await store.recordSighting(device)

        let records = try await store.allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].connectionCount, 3)
    }

    func testRandomizedMacRecordedWithoutVendor() async throws {
        let store = try makeStore()
        try await store.recordSighting(makeDevice(mac: "8a:3f:19:00:11:22", randomized: true))

        let records = try await store.allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].isRandomizedMAC)
        XCTAssertNil(records[0].vendor)
        XCTAssertEqual(records[0].displayName, "Private/Randomized Address")
    }

    func testSetLabelOverridesDisplayName() async throws {
        let store = try makeStore()
        try await store.recordSighting(makeDevice(mac: "a4:83:e7:12:34:56", randomized: false))
        let recordID = try await store.allRecords()[0].id!
        try await store.setLabel(recordID: recordID, label: "Alex's iPhone")

        let records = try await store.allRecords()
        XCTAssertEqual(records[0].displayName, "Alex's iPhone")
    }

    func testDeleteRecordRemovesIt() async throws {
        let store = try makeStore()
        try await store.recordSighting(makeDevice(mac: "a4:83:e7:12:34:56", randomized: false))
        let recordID = try await store.allRecords()[0].id!
        try await store.deleteRecord(id: recordID)

        let records = try await store.allRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testDeleteAllClearsHistory() async throws {
        let store = try makeStore()
        try await store.recordSighting(makeDevice(mac: "a4:83:e7:12:34:56", randomized: false))
        try await store.recordSighting(makeDevice(mac: "8a:3f:19:00:11:22", randomized: true))
        try await store.deleteAll()

        let records = try await store.allRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testSetBlockedTracksBlockedRecords() async throws {
        let store = try makeStore()
        try await store.recordSighting(makeDevice(mac: "a4:83:e7:12:34:56", randomized: false))
        try await store.recordSighting(makeDevice(mac: "8a:3f:19:00:11:22", randomized: true))
        let records = try await store.allRecords()
        let toBlock = records.first { $0.mac == "a4:83:e7:12:34:56" }!.id!

        try await store.setBlocked(recordID: toBlock, blocked: true)

        let blocked = try await store.blockedRecords()
        XCTAssertEqual(blocked.count, 1)
        XCTAssertEqual(blocked[0].mac, "a4:83:e7:12:34:56")

        try await store.setBlocked(recordID: toBlock, blocked: false)
        let blockedAfterUnblock = try await store.blockedRecords()
        XCTAssertTrue(blockedAfterUnblock.isEmpty)
    }

    func testDataSurvivesReopenViaEncryptedRestFile() async throws {
        let restURL = tempDir.appendingPathComponent("history.sqlite.enc")
        let key = SymmetricKey(size: .bits256)

        let store1 = try DeviceHistoryStore(restFileURL: restURL, key: key)
        try await store1.recordSighting(makeDevice(mac: "a4:83:e7:12:34:56", randomized: false))
        await store1.shutdown()

        XCTAssertTrue(FileManager.default.fileExists(atPath: restURL.path))

        let store2 = try DeviceHistoryStore(restFileURL: restURL, key: key)
        let records = try await store2.allRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].mac, "a4:83:e7:12:34:56")
    }

    func testWrongKeyCannotDecryptRestFile() async throws {
        let restURL = tempDir.appendingPathComponent("history.sqlite.enc")
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)

        let store1 = try DeviceHistoryStore(restFileURL: restURL, key: key1)
        try await store1.recordSighting(makeDevice(mac: "a4:83:e7:12:34:56", randomized: false))
        await store1.shutdown()

        XCTAssertThrowsError(try DeviceHistoryStore(restFileURL: restURL, key: key2))
    }
}
