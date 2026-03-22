import SwiftUI
import UIKit

struct CaptureTimelineView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var isShowingCamera = false
    @State private var pendingImage: UIImage?

    var body: some View {
        List {
            Section {
                Text("Capture explicit snapshots when you want a breadcrumb. Each saved frame stays local and can optionally be tagged with the items visible in it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            if appModel.orderedSnapshots.isEmpty {
                Section {
                    EmptyStateView(
                        title: "No breadcrumbs yet",
                        message: "Save a few snapshots during your day so Breadcrumb has recent context to search.",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                Section("Recent Timeline") {
                    ForEach(appModel.orderedSnapshots) { snapshot in
                        snapshotRow(snapshot)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Capture")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Capture", systemImage: "camera")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isShowingCamera = true
            } label: {
                Label("Capture Breadcrumb", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .padding(.horizontal)
            .padding(.top, 8)
            .background(.thinMaterial)
        }
        .sheet(isPresented: $isShowingCamera) {
            CameraCaptureView(
                title: "Capture Breadcrumb",
                subtitle: "Save a single frame that could help you reconstruct this moment later."
            ) { image in
                pendingImage = image
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingImage != nil },
            set: { if !$0 { pendingImage = nil } }
        )) {
            if let pendingImage {
                NavigationStack {
                    SnapshotReviewView(image: pendingImage) {
                        self.pendingImage = nil
                    }
                }
            }
        }
    }

    private func snapshotRow(_ snapshot: TimelineSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                StoredImageView(relativePath: snapshot.imagePath, cornerRadius: 16)
                    .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)

                    if snapshot.hasContextNote {
                        Text(snapshot.contextNote)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } else {
                        Text("No context note")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if !snapshot.visibleItemIDs.isEmpty {
                let lookup = appModel.library.itemNameLookup()
                let names = snapshot.visibleItemIDs.compactMap { lookup[$0] }
                if !names.isEmpty {
                    Text("Visible items: \(names.joined(separator: ", "))")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.indigo)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
