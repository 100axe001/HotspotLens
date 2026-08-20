import Foundation
import HotspotLensCore

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var records: [DeviceRecord] = []
    @Published var lastError: String?

    private let store: DeviceHistoryStore?

    init(store: DeviceHistoryStore?) {
        self.store = store
    }

    func reload() async {
        guard let store else { return }
        do {
            records = try await store.allRecords()
        } catch {
            lastError = "Couldn't load history: \(error)"
        }
    }

    func setLabel(_ label: String, for record: DeviceRecord) async {
        guard let store, let id = record.id else { return }
        do {
            try await store.setLabel(recordID: id, label: label)
            await reload()
        } catch {
            lastError = "Couldn't save label: \(error)"
        }
    }

    func delete(_ record: DeviceRecord) async {
        guard let store, let id = record.id else { return }
        do {
            try await store.deleteRecord(id: id)
            await reload()
        } catch {
            lastError = "Couldn't delete this device's history: \(error)"
        }
    }

    func deleteAll() async {
        guard let store else { return }
        do {
            try await store.deleteAll()
            await reload()
        } catch {
            lastError = "Couldn't clear history: \(error)"
        }
    }
}
