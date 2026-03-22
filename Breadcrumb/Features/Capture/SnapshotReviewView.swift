import SwiftUI
import UIKit

struct SnapshotReviewView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onSave: () -> Void

    @State private var note = ""
    @State private var selectedItemIDs = Set<UUID>()
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Preview") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            Section("Context Note") {
                TextField("Optional context, like \"kitchen counter after breakfast\"", text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }

            if !appModel.orderedItems.isEmpty {
                Section("Items Visible In This Shot") {
                    ForEach(appModel.orderedItems) { item in
                        Toggle(isOn: binding(for: item.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.body.weight(.medium))
                                if !item.detail.isEmpty {
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Review Breadcrumb")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Discard") {
                    onSave()
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
            }
        }
        .alert("Couldn't Save Snapshot", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func binding(for itemID: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedItemIDs.contains(itemID) },
            set: { isSelected in
                if isSelected {
                    selectedItemIDs.insert(itemID)
                } else {
                    selectedItemIDs.remove(itemID)
                }
            }
        )
    }

    private func save() {
        do {
            try appModel.saveSnapshot(image: image, note: note, visibleItemIDs: selectedItemIDs)
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
