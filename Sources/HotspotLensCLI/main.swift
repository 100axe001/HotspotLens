import Foundation
import HotspotLensCore

let service = DeviceDiscoveryService()
let snapshot = service.discover()

switch snapshot.hotspotState {
case .inactive:
    print("Internet Sharing is off. Turn it on in System Settings > General > Sharing to see connected devices.")
    exit(0)
case .indeterminate(let reason):
    print("Could not determine Internet Sharing status: \(reason)")
    exit(1)
case .active(let interface):
    print("Internet Sharing is active on \(interface).")
}

func padded(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

if snapshot.devices.isEmpty {
    print("No devices connected yet.")
} else {
    print("\(snapshot.devices.count) device\(snapshot.devices.count == 1 ? "" : "s") connected:\n")
    print(padded("MAC", 19) + padded("IPv4", 15) + padded("Vendor / Label", 30) + "Source")
    for device in snapshot.devices {
        let source = [
            device.sources.contains(.arp) ? "arp" : nil,
            device.sources.contains(.ndp) ? "ndp" : nil,
            device.sources.contains(.dhcpLease) ? "dhcp" : nil
        ].compactMap { $0 }.joined(separator: "+")

        print(
            padded(device.mac.description, 19) +
            padded(device.ipv4 ?? "-", 15) +
            padded(device.defaultDisplayName, 30) +
            source
        )
    }
}

if !snapshot.warnings.isEmpty {
    print("\nWarnings:")
    for warning in snapshot.warnings {
        print("  - \(warning)")
    }
}
