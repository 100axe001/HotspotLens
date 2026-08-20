import SwiftUI
import HotspotLensCore

struct HistoryTabView: View {
    @EnvironmentObject private var history: HistoryViewModel
    @State private var editingRecord: DeviceRecord?
    @State private var confirmingClearAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if history.records.isEmpty {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "No history yet",
                    message: "Devices you've seen before will show up here, with how often they've connected."
                )
            } else {
                HStack {
                    Spacer()
                    Button("Clear All History", role: .destructive) {
                        confirmingClearAll = true
                    }
                    .font(Theme.captionFont)
                }

                ForEach(history.records) { record in
                    HistoryRow(record: record) {
                        editingRecord = record
                    } onDelete: {
                        Task { await history.delete(record) }
                    }
                    .themedCard()
                }
            }
        }
        .task { await history.reload() }
        .sheet(item: $editingRecord) { record in
            LabelEditSheet(record: record) { newLabel in
                Task { await history.setLabel(newLabel, for: record) }
                editingRecord = nil
            } onCancel: {
                editingRecord = nil
            }
        }
        .confirmationDialog(
            "Clear all device history?",
            isPresented: $confirmingClearAll,
            titleVisibility: .visible
        ) {
            Button("Clear All History", role: .destructive) {
                Task { await history.deleteAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes labels and connection history for every device. Devices currently connected will still show up live.")
        }
    }
}

private struct HistoryRow: View {
    let record: DeviceRecord
    let onEditLabel: () -> Void
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayName)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
                Text(record.mac)
                    .font(Theme.monoCaptionFont)
                    .foregroundStyle(Theme.textSecondary)
                if record.isRandomizedMAC {
                    Text("Private address -- this may be one of several entries for the same physical device, since its address changes per network.")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("Seen \(record.connectionCount) time\(record.connectionCount == 1 ? "" : "s") · last on \(Self.dateFormatter.string(from: record.lastSeen))")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Menu {
                Button("Edit Label", action: onEditLabel)
                Button("Delete History", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
    }
}
