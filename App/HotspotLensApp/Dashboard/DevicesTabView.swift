import SwiftUI
import HotspotLensCore

struct DevicesTabView: View {
    @EnvironmentObject private var discovery: DiscoveryViewModel
    @Binding var pendingBlockDevice: Device?

    var body: some View {
        switch discovery.hotspotState {
        case .inactive:
            EmptyStateView(
                systemImage: "wifi.slash",
                title: "Internet Sharing is off",
                message: "Turn it on in System Settings > General > Sharing to start seeing connected devices."
            )
        case .indeterminate(let reason):
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Can't check sharing status",
                message: reason
            )
        case .active:
            if discovery.devices.isEmpty {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "No devices connected yet",
                    message: "New connections will appear here automatically."
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(discovery.devices) { device in
                        DeviceRow(device: device, style: .full) {
                            pendingBlockDevice = device
                        }
                        .themedCard()
                    }
                }
                if !discovery.warnings.isEmpty {
                    ForEach(discovery.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}
