import Foundation

struct TimelineSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var imagePath: String
    var capturedAt: Date
    var contextNote: String
    var visibleItemIDs: [UUID]

    var hasContextNote: Bool {
        !contextNote.isEmpty
    }
}
