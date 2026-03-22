import SwiftUI
import UIKit

struct RegisterItemView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var detail = ""
    @State private var referenceImages: [UIImage] = []
    @State private var isShowingCamera = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Item") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                TextField("Optional note", text: $detail, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Text("This MVP works best when you capture 2-3 clean reference photos from different angles against a simple background.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Reference Photos") {
                if referenceImages.isEmpty {
                    EmptyStateView(
                        title: "No reference photos yet",
                        message: "Capture at least one clear photo so Breadcrumb can compare future snapshots on-device.",
                        systemImage: "camera.macro"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(referenceImages.enumerated()), id: \.offset) { entry in
                                let image = entry.element
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Button {
                    isShowingCamera = true
                } label: {
                    Label("Capture reference photo", systemImage: "camera")
                }
            }
        }
        .navigationTitle("Register Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    save()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || referenceImages.isEmpty)
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraCaptureView(
                title: "Reference Capture",
                subtitle: "Frame the object clearly and keep it large in the shot."
            ) { image in
                referenceImages.append(image)
            }
        }
        .alert("Couldn't Save Item", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        do {
            try appModel.createItem(name: name, detail: detail, referenceImages: referenceImages)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
