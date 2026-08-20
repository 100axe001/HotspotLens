import SwiftUI
import HotspotLensCore

/// One clear dialog before blocking -- blocking affects a real person on
/// the other end of this hotspot, so it gets a deliberate, low-friction
/// confirmation rather than being a single accidental click away.
struct BlockConfirmationDialog: View {
    let device: Device
    let onDismiss: () -> Void

    @EnvironmentObject private var blocking: BlockingCoordinator
    @EnvironmentObject private var history: HistoryViewModel
    @State private var isBlocking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(Theme.destructive)
                    .font(.title2)
                Text("Block \(device.defaultDisplayName)?")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.textPrimary)
            }

            Text("This device won't be able to use the internet through this Mac's hotspot until you unblock it. Blocking is always visible here in the Blocked tab -- there's no hidden or silent blocking mode.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textSecondary)

            if let ip = device.ipv4 {
                Text("\(ip) · \(device.mac.description)")
                    .font(Theme.monoCaptionFont)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("This device has no current IPv4 address, so it can't be blocked right now.")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.destructive)
            }

            HStack {
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.bordered)
                Button {
                    Task { await confirmBlock() }
                } label: {
                    if isBlocking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Block Device")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.destructive)
                .disabled(device.ipv4 == nil || isBlocking)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.background)
    }

    private func confirmBlock() async {
        guard let ip = device.ipv4 else { return }
        isBlocking = true
        defer { isBlocking = false }

        // recordSighting already upserted this device via DiscoveryViewModel,
        // so a history record should exist; if history is unavailable this
        // lookup legitimately comes back empty and we surface that instead
        // of guessing.
        await history.reload()
        guard let record = history.records.first(where: { $0.mac == device.mac.description }) else {
            blocking.lastError = "Couldn't find this device in history yet -- try again in a moment."
            return
        }

        await blocking.block(record: record, ipv4: ip)
        onDismiss()
    }
}
