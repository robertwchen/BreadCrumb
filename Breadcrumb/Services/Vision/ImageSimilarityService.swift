import UIKit
import Vision

enum ImageSimilarityError: LocalizedError {
    case invalidImage
    case noFeaturePrint

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The image could not be processed."
        case .noFeaturePrint:
            return "Vision could not generate a feature print for this image."
        }
    }
}

final class ImageSimilarityService: @unchecked Sendable {
    private let cache = NSCache<NSString, VNFeaturePrintObservation>()

    func distance(
        between lhsPath: String,
        and rhsPath: String,
        imageLoader: (String) -> UIImage?
    ) throws -> Double {
        let lhsObservation = try featurePrint(for: lhsPath, imageLoader: imageLoader)
        let rhsObservation = try featurePrint(for: rhsPath, imageLoader: imageLoader)

        var distance: Float = 0
        try lhsObservation.computeDistance(&distance, to: rhsObservation)
        return Double(distance)
    }

    private func featurePrint(
        for relativePath: String,
        imageLoader: (String) -> UIImage?
    ) throws -> VNFeaturePrintObservation {
        if let cached = cache.object(forKey: relativePath as NSString) {
            return cached
        }

        guard let image = imageLoader(relativePath), let cgImage = normalizedCGImage(from: image) else {
            throw ImageSimilarityError.invalidImage
        }

        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw ImageSimilarityError.noFeaturePrint
        }

        cache.setObject(observation, forKey: relativePath as NSString)
        return observation
    }

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage {
            return cgImage
        }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: rendererFormat)
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return normalizedImage.cgImage
    }
}
