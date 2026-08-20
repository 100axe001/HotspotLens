import SwiftUI
import HotspotLensCore

struct LabelEditSheet: View {
    let record: DeviceRecord
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var label: String

    init(record: DeviceRecord, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.record = record
        self.onSave = onSave
        self.onCancel = onCancel
        _label = State(initialValue: record.label ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Label this device")
                .font(Theme.titleFont)
                .foregroundStyle(Theme.textPrimary)

            Text(record.mac)
                .font(Theme.monoCaptionFont)
                .foregroundStyle(Theme.textSecondary)

            TextField("e.g. Alex's iPhone", text: $label)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Save") { onSave(label) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Theme.background)
    }
}
