import Foundation
import UIKit

enum AssetFolder: String {
    case references
    case snapshots
}

enum BreadcrumbStoreError: LocalizedError {
    case couldNotEncodeImage

    var errorDescription: String? {
        switch self {
        case .couldNotEncodeImage:
            return "The captured image could not be saved."
        }
    }
}

final class LibraryStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadLibrary() throws -> BreadcrumbLibrary {
        try ensureDirectories()

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return BreadcrumbLibrary()
        }

        let data = try Data(contentsOf: metadataURL)
        return try decoder.decode(BreadcrumbLibrary.self, from: data)
    }

    func saveLibrary(_ library: BreadcrumbLibrary) throws {
        try ensureDirectories()
        let data = try encoder.encode(library)
        try data.write(to: metadataURL, options: .atomic)
    }

    func saveJPEG(_ image: UIImage, id: UUID, folder: AssetFolder, compression: CGFloat = 0.82) throws -> String {
        try ensureDirectories()

        guard let data = image.jpegData(compressionQuality: compression) else {
            throw BreadcrumbStoreError.couldNotEncodeImage
        }

        let relativePath = "\(folder.rawValue)/\(id.uuidString).jpg"
        let fileURL = rootURL.appendingPathComponent(relativePath)
        try data.write(to: fileURL, options: .atomic)
        return relativePath
    }

    func loadImage(relativePath: String) -> UIImage? {
        let fileURL = rootURL.appendingPathComponent(relativePath)
        return UIImage(contentsOfFile: fileURL.path)
    }

    private var rootURL: URL {
        let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent("BreadcrumbData", isDirectory: true)
    }

    private var metadataURL: URL {
        rootURL.appendingPathComponent("library.json")
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(
            at: rootURL.appendingPathComponent(AssetFolder.references.rawValue),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try fileManager.createDirectory(
            at: rootURL.appendingPathComponent(AssetFolder.snapshots.rawValue),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
