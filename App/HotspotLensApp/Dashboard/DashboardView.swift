import SwiftUI
import HotspotLensCore

struct DashboardView: View {
    let historyLoadError: String?

    @EnvironmentObject private var discovery: DiscoveryViewModel
    @EnvironmentObject private var history: HistoryViewModel
    @EnvironmentObject private var helper: PrivilegedHelperManager
    @EnvironmentObject private var blocking: BlockingCoordinator

    @State private var selectedTab: Tab = .devices
    @State private var pendingBlockDevice: Device?

    enum Tab: String, CaseIterable, Identifiable {
        case devices = "Devices"
        case history = "History"
        case blocked = "Blocked"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let historyLoadError {
                Banner(
                    systemImage: "exclamationmark.triangle.fill",
                    text: "History is unavailable right now, so labels and past devices won't be shown (live device detection still works). Details: \(historyLoadError)"
                )
            }
            if let error = history.lastError ?? blocking.lastError {
                Banner(systemImage: "exclamationmark.circle", text: error)
            }

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(16)

            Divider().overlay(Theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedTab {
                    case .devices:
                        DevicesTabView(pendingBlockDevice: $pendingBlockDevice)
                    case .history:
                        HistoryTabView()
                    case .blocked:
                        BlockedTabView()
                    }
                }
                .padding(16)
            }
        }
        .sheet(item: $pendingBlockDevice) { device in
            BlockConfirmationDialog(device: device) {
                pendingBlockDevice = nil
            }
        }
    }
}

private struct Banner: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(Theme.destructive)
            Text(text)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(10)
        .background(Theme.accentSubtle, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
        .padding([.horizontal, .top], 16)
    }
}
