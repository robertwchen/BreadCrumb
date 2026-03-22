import Foundation

struct BreadcrumbLibrary: Codable, Hashable, Sendable {
    var items: [TrackedItem] = []
    var snapshots: [TimelineSnapshot] = []

    func orderedSnapshotsDescending() -> [TimelineSnapshot] {
        snapshots.sorted { $0.capturedAt > $1.capturedAt }
    }

    func contextStrip(around snapshotID: UUID, leading: Int = 1, trailing: Int = 1) -> [TimelineSnapshot] {
        let ordered = orderedSnapshotsDescending()
        guard let index = ordered.firstIndex(where: { $0.id == snapshotID }) else {
            return []
        }

        let lowerBound = max(ordered.startIndex, index - leading)
        let upperBound = min(ordered.index(before: ordered.endIndex), index + trailing)
        return Array(ordered[lowerBound...upperBound])
    }

    func itemNameLookup() -> [UUID: String] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.name) })
    }
}
