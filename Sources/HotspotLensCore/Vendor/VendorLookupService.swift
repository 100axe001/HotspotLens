import Foundation

/// Looks up a hardware vendor name from a MAC's OUI (first three octets)
/// using a bundled, local JSON file -- never a network call.
///
/// Locally-administered (randomized) MACs are refused outright: their OUI
/// carries no IEEE vendor assignment, so guessing from it would be actively
/// misleading. Callers should check `MACAddress.isLocallyAdministered`
/// first (see `DeviceDiscoveryService`), but this type double-checks so it
/// can never be misused into fabricating a vendor for a private address.
public struct VendorLookupService: Sendable {
    private let table: [String: String]

    public enum LoadError: Error, Sendable {
        case resourceMissing
        case decodeFailed(underlying: Error)
    }

    /// Loads `oui_vendors.json` from the package's resource bundle.
    public init() throws {
        guard let url = Bundle.module.url(forResource: "oui_vendors", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        do {
            self.table = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw LoadError.decodeFailed(underlying: error)
        }
    }

    /// Test/CLI-friendly initializer taking an already-loaded table.
    public init(table: [String: String]) {
        self.table = table
    }

    /// Returns the vendor name for `mac`'s OUI, or `nil` if the OUI is not
    /// in the bundled table (an unknown OUI -- not an error, just data we
    /// don't have) or if the address is locally administered.
    public func vendor(for mac: MACAddress) -> String? {
        guard !mac.isLocallyAdministered else { return nil }
        return table[mac.organizationallyUniqueIdentifier.lowercased()]
    }

    public var entryCount: Int { table.count }
}
