import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var library = BreadcrumbLibrary()
    @Published private(set) var hasLoaded = false

    private let store: LibraryStore
    private let searchService: SearchService

    init(
        store: LibraryStore = LibraryStore(),
        searchService: SearchService? = nil
    ) {
        self.store = store
        self.searchService = searchService ?? SearchService(store: store)
    }

    var orderedItems: [TrackedItem] {
        library.items.sorted { $0.createdAt > $1.createdAt }
    }

    var orderedSnapshots: [TimelineSnapshot] {
        library.snapshots.sorted { $0.capturedAt > $1.capturedAt }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        defer { hasLoaded = true }

        do {
            library = try store.loadLibrary()
        } catch {
            library = BreadcrumbLibrary()
            print("Breadcrumb load failed: \(error.localizedDescription)")
        }
    }

    func createItem(name: String, detail: String, referenceImages: [UIImage]) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        var referencePhotos: [ReferencePhoto] = []
        for image in referenceImages {
            let id = UUID()
            let relativePath = try store.saveJPEG(image, id: id, folder: .references)
            referencePhotos.append(
                ReferencePhoto(
                    id: id,
                    imagePath: relativePath,
                    capturedAt: Date()
                )
            )
        }

        let item = TrackedItem(
            id: UUID(),
            name: cleanName,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(),
            referencePhotos: referencePhotos
        )

        library.items.insert(item, at: 0)
        try persist()
    }

    func addReferenceImage(_ image: UIImage, to itemID: UUID) throws {
        guard let index = library.items.firstIndex(where: { $0.id == itemID }) else { return }

        let referenceID = UUID()
        let relativePath = try store.saveJPEG(image, id: referenceID, folder: .references)
        library.items[index].referencePhotos.append(
            ReferencePhoto(
                id: referenceID,
                imagePath: relativePath,
                capturedAt: Date()
            )
        )
        try persist()
    }

    func saveSnapshot(image: UIImage, note: String, visibleItemIDs: Set<UUID>) throws {
        let snapshotID = UUID()
        let relativePath = try store.saveJPEG(image, id: snapshotID, folder: .snapshots)

        let snapshot = TimelineSnapshot(
            id: snapshotID,
            imagePath: relativePath,
            capturedAt: Date(),
            contextNote: note.trimmingCharacters(in: .whitespacesAndNewlines),
            visibleItemIDs: Array(visibleItemIDs)
        )

        library.snapshots.insert(snapshot, at: 0)
        try persist()
    }

    func image(for relativePath: String) -> UIImage? {
        store.loadImage(relativePath: relativePath)
    }

    func search(for item: TrackedItem) async -> SearchResult? {
        let librarySnapshot = library
        let service = searchService
        return await Task.detached(priority: .userInitiated) {
            service.findLastSeen(for: item, in: librarySnapshot)
        }.value
    }

    private func persist() throws {
        try store.saveLibrary(library)
    }
}
