import Foundation
import Combine
import HotspotLensCore

/// Polls `DeviceDiscoveryService` on a timer and publishes the live
/// device list for both the menu bar popover and the dashboard's Devices
/// tab. Also feeds `DeviceHistoryStore`, but deliberately not on every
/// single poll tick for a device that's continuously connected -- that
/// would mean re-encrypting the history file every few seconds for no
/// benefit. Instead: record immediately on a device's first appearance in a
/// session, then at most once per `historyHeartbeatInterval` after that.
@MainActor
final class DiscoveryViewModel: ObservableObject {
    @Published private(set) var hotspotState: HotspotState = .indeterminate(reason: "Not checked yet")
    @Published private(set) var devices: [Device] = []
    @Published private(set) var warnings: [String] = []
    @Published private(set) var lastUpdated: Date?

    private let discoveryService: DeviceDiscoveryService
    private let historyStore: DeviceHistoryStore?
    private var timer: Timer?
    private var lastRecordedAt: [String: Date] = [:]
    private let pollInterval: TimeInterval
    private let historyHeartbeatInterval: TimeInterval

    init(
        discoveryService: DeviceDiscoveryService = DeviceDiscoveryService(),
        historyStore: DeviceHistoryStore?,
        pollInterval: TimeInterval = 5,
        historyHeartbeatInterval: TimeInterval = 300
    ) {
        self.discoveryService = discoveryService
        self.historyStore = historyStore
        self.pollInterval = pollInterval
        self.historyHeartbeatInterval = historyHeartbeatInterval
    }

    func start() {
        pollOnce()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pollOnce() {
        // Discovery hits the filesystem/subprocesses; keep it off the main
        // actor so the popover never stutters opening.
        let service = discoveryService
        Task.detached(priority: .userInitiated) { [weak self] in
            let snapshot = service.discover()
            await self?.apply(snapshot)
        }
    }

    private func apply(_ snapshot: DiscoverySnapshot) async {
        hotspotState = snapshot.hotspotState
        devices = snapshot.devices
        warnings = snapshot.warnings
        lastUpdated = snapshot.takenAt

        guard let historyStore else { return }
        let now = snapshot.takenAt
        for device in snapshot.devices {
            let key = device.id
            let lastRecorded = lastRecordedAt[key]
            let dueForHeartbeat = lastRecorded.map { now.timeIntervalSince($0) >= historyHeartbeatInterval } ?? true
            guard dueForHeartbeat else { continue }
            lastRecordedAt[key] = now
            do {
                try await historyStore.recordSighting(device)
            } catch {
                // History is best-effort supplementary data; a write hiccup
                // here must never take down live discovery.
                warnings.append("Could not update history for \(device.id): \(error)")
            }
        }
    }
}
