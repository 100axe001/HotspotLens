import SwiftUI
import HotspotLensCore

/// Shows vendor/label as the primary line and MAC/IP as secondary detail --
/// plain language first, networking jargon second. Used in the menu bar
/// popover (`.compact`) and the dashboard Devices tab (`.full`).
struct DeviceRow: View {
    enum Style { case compact, full }

    let device: Device
    var style: Style = .full
    var onBlockTapped: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.identity.isRandomized ? "questionmark.circle" : "iphone.gen3")
                .foregroundStyle(device.identity.isRandomized ? Theme.textSecondary : Theme.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.defaultDisplayName)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(secondaryLine)
                    .font(Theme.monoCaptionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if style == .full, let onBlockTapped {
                Button("Block", role: .destructive, action: onBlockTapped)
                    .buttonStyle(.bordered)
                    .tint(Theme.destructive)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, style == .full ? 4 : 0)
    }

    private var secondaryLine: String {
        var parts: [String] = []
        if let ipv4 = device.ipv4 { parts.append("IP: \(ipv4)") }
        parts.append("MAC: \(device.mac.description)")
        if device.identity.isRandomized {
            parts.append("Private MAC")
        }
        return parts.joined(separator: "  •  ")
    }
}
