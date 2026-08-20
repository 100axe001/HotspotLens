import SwiftUI
import HotspotLensCore

@main
struct HotspotLensApp: App {
    @StateObject private var discovery: DiscoveryViewModel
    @StateObject private var history: HistoryViewModel
    @StateObject private var helper: PrivilegedHelperManager
    @StateObject private var blocking: BlockingCoordinator

    private let historyStore: DeviceHistoryStore?
    private let historyLoadError: String?

    init() {
        var store: DeviceHistoryStore?
        var loadError: String?
        do {
            store = try DeviceHistoryStore()
        } catch {
            // History is supplementary, not required for the core "who's
            // on my network right now" feature -- degrade to a live-only
            // mode with a visible explanation rather than crashing at
            // launch. See ContentUnavailableHistoryBanner.
            loadError = "\(error)"
        }
        self.historyStore = store
        self.historyLoadError = loadError

        let helperManager = PrivilegedHelperManager()
        let disc = DiscoveryViewModel(historyStore: store)
        disc.start()
        _discovery = StateObject(wrappedValue: disc)
        _history = StateObject(wrappedValue: HistoryViewModel(store: store))
        _helper = StateObject(wrappedValue: helperManager)
        _blocking = StateObject(wrappedValue: BlockingCoordinator(store: store, helper: helperManager))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(discovery)
                .environmentObject(helper)
                .environmentObject(blocking)
        } label: {
            MenuBarLabel()
                .environmentObject(discovery)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: discovery.devices) { _, devices in
            Task { await blocking.reconcile(with: devices) }
        }

        Window("HotspotLens", id: "dashboard") {
            DashboardView(historyLoadError: historyLoadError)
                .environmentObject(discovery)
                .environmentObject(history)
                .environmentObject(helper)
                .environmentObject(blocking)
                .frame(minWidth: 640, minHeight: 440)
                .background(Theme.background)
                .task {
                    discovery.start()
                    await history.reload()
                    helper.refreshStatus()
                    await blocking.reload()
                }
        }
        .defaultSize(width: 720, height: 520)
    }
}

/// The always-visible menu bar icon + optional device-count badge.
private struct MenuBarLabel: View {
    @EnvironmentObject private var discovery: DiscoveryViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            if case .active = discovery.hotspotState, !discovery.devices.isEmpty {
                Text("\(discovery.devices.count)")
            }
        }
        .task { discovery.start() }
    }

    private var iconName: String {
        switch discovery.hotspotState {
        case .active: return "wifi.circle.fill"
        case .inactive: return "wifi.slash"
        case .indeterminate: return "wifi.exclamationmark"
        }
    }
}
