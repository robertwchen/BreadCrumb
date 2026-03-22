import SwiftUI

struct ItemLibraryView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var isShowingRegisterSheet = false
    @State private var captureTargetItemID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Track one or two critical items with a few clear reference photos. Wallets and pill bottles are strong demo objects for this MVP.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            if appModel.orderedItems.isEmpty {
                Section {
                    EmptyStateView(
                        title: "No items registered yet",
                        message: "Add a pill bottle, wallet, or another important item with a few reference photos to start building breadcrumbs.",
                        systemImage: "shippingbox"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Tracked Items") {
                    ForEach(appModel.orderedItems) { item in
                        itemRow(for: item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reference Items")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingRegisterSheet = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingRegisterSheet) {
            NavigationStack {
                RegisterItemView()
            }
            .presentationDetents([.large])
        }
        .sheet(item: Binding(
            get: { captureTargetItemID.map(CaptureTarget.init(id:)) },
            set: { captureTargetItemID = $0?.id }
        )) { target in
            CameraCaptureView(
                title: "Add Reference Photo",
                subtitle: "Capture a clear image of the registered item from another angle."
            ) { image in
                do {
                    try appModel.addReferenceImage(image, to: target.id)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("Save Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func itemRow(for item: TrackedItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if let primaryReference = item.referencePhotos.first {
                    StoredImageView(relativePath: primaryReference.imagePath, cornerRadius: 16)
                        .frame(width: 84, height: 84)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.headline)

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(item.referencePhotos.count) reference photo\(item.referencePhotos.count == 1 ? "" : "s")")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.indigo)
                }

                Spacer()
            }

            Button {
                captureTargetItemID = item.id
            } label: {
                Label("Add another reference angle", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding(.vertical, 6)
    }
}

private struct CaptureTarget: Identifiable {
    let id: UUID
}
