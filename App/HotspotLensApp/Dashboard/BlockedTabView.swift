import SwiftUI
import HotspotLensCore

struct BlockedTabView: View {
    @EnvironmentObject private var blocking: BlockingCoordinator
    @EnvironmentObject private var helper: PrivilegedHelperManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            helperStatusBanner

            if blocking.blockedRecords.isEmpty {
                EmptyStateView(
                    systemImage: "hand.raised",
                    title: "No blocked devices",
                    message: "Block a device from the Devices tab to stop it from using this hotspot."
                )
            } else {
                ForEach(blocking.blockedRecords) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.displayName)
                                .font(Theme.bodyFont)
                                .foregroundStyle(Theme.textPrimary)
                            Text([record.lastKnownIPv4, record.mac].compactMap { $0 }.joined(separator: " · "))
                                .font(Theme.monoCaptionFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button("Unblock") {
                            Task { await blocking.unblock(record: record) }
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                        .controlSize(.small)
                    }
                    .themedCard()
                }
            }
        }
        .task {
            helper.refreshStatus()
            await blocking.reload()
        }
    }

    @ViewBuilder
    private var helperStatusBanner: some View {
        switch helper.availability {
        case .ready, .unknown:
            EmptyView()
        case .notRegistered:
            EmptyView()
        case .awaitingApproval:
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                Text("Blocking needs one-time approval: open System Settings > General > Login Items & Extensions and allow HotspotLens Helper.")
                    .font(Theme.captionFont)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(10)
            .background(Theme.accentSubtle, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
        case .failed(let reason):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Blocking is unavailable: \(reason)")
                    .font(Theme.captionFont)
            }
            .foregroundStyle(Theme.destructive)
            .padding(10)
            .background(Theme.accentSubtle, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
        }
    }
}
