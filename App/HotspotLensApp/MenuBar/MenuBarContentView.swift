import SwiftUI
import AppKit
import HotspotLensCore

/// What appears when the user clicks the menu bar icon: status, count, and
/// a short live list -- everything for the common "who's on my network"
/// question, with zero extra clicks.
struct MenuBarContentView: View {
    @EnvironmentObject private var discovery: DiscoveryViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            switch discovery.hotspotState {
            case .inactive:
                EmptyStateView(
                    systemImage: "wifi.slash",
                    title: "Internet Sharing is off",
                    message: "Turn it on in System Settings > General > Sharing to see who connects."
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
                        message: "New connections appear here within a few seconds."
                    )
                } else {
                    deviceList
                }
            }

            Divider()

            HStack {
                Button("Open Dashboard") {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit HotspotLens") {
                    NSApp.terminate(nil)
                }
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .font(Theme.captionFont)
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.background)
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Theme.accent : Theme.textSecondary.opacity(0.4))
                .frame(width: 9, height: 9)
            Text(headerText)
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
    }

    private var isActive: Bool {
        if case .active = discovery.hotspotState { return true }
        return false
    }

    private var headerText: String {
        switch discovery.hotspotState {
        case .active:
            let count = discovery.devices.count
            return "\(count) device\(count == 1 ? "" : "s") connected"
        case .inactive:
            return "Sharing is off"
        case .indeterminate:
            return "Status unknown"
        }
    }

    private var deviceList: some View {
        VStack(spacing: 6) {
            ForEach(discovery.devices.prefix(6)) { device in
                DeviceRow(device: device, style: .compact)
            }
            if discovery.devices.count > 6 {
                Text("+ \(discovery.devices.count - 6) more in Dashboard")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
