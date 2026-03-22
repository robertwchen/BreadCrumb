import SwiftUI
import UIKit

struct RegisterItemView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var notes = ""
    @State private var referenceImages: [UIImage] = []
    @State private var isShowingCamera = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Tracked Object") {
                TextField("Object name", text: $name)
                    .textInputAutocapitalization(.words)

                TextField("Notes about where it belongs or how to recognize it", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Text("Reference photos are optional. Breadcrumb can discover candidates on its own, and extra photos only help future re-identification once you care about a specific object.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Optional Reference Photos") {
                if referenceImages.isEmpty {
                    EmptyStateView(
                        title: "No reference photos yet",
                        message: "You can save this object now and add photos later if you want stronger identity matching.",
                        systemImage: "camera.macro"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(referenceImages.enumerated()), id: \.offset) { entry in
                                Image(uiImage: entry.element)
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
                    Label("Capture optional photo", systemImage: "camera")
                }
            }
        }
        .navigationTitle("New Object")
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
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraCaptureView(
                title: "Reference Capture",
                subtitle: "Optional photos work best when the object is clear and fills most of the frame."
            ) { image in
                referenceImages.append(image)
            }
        }
        .alert("Couldn't Save Object", isPresented: Binding(
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
            try appModel.createTrackedObject(name: name, notes: notes, referenceImages: referenceImages)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
