import Foundation

struct TrackedItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var detail: String
    var createdAt: Date
    var referencePhotos: [ReferencePhoto]

    var hasReferencePhotos: Bool {
        !referencePhotos.isEmpty
    }
}

struct ReferencePhoto: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var imagePath: String
    var capturedAt: Date
}
