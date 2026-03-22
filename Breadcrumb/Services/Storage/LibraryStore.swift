import Foundation
import UIKit

enum AssetFolder: String {
    case references
    case candidateEvidence
    case eventEvidence
}

enum BreadcrumbStoreError: LocalizedError {
    case couldNotEncodeImage

    var errorDescription: String? {
        switch self {
        case .couldNotEncodeImage:
            return "The image could not be saved."
        }
    }
}

final class LibraryStore: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func saveJPEG(_ image: UIImage, id: UUID, folder: AssetFolder, compression: CGFloat = 0.72) throws -> String {
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

    func resetAllData() throws {
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
    }

    private var rootURL: URL {
        let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent("BreadcrumbAssets", isDirectory: true)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)

        for folder in [AssetFolder.references, .candidateEvidence, .eventEvidence] {
            try fileManager.createDirectory(
                at: rootURL.appendingPathComponent(folder.rawValue),
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
}
