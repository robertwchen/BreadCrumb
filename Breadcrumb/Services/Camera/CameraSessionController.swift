import AVFoundation
import SwiftUI
import UIKit

enum CameraCaptureError: LocalizedError {
    case permissionDenied
    case configurationFailed
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access is required to capture breadcrumbs."
        case .configurationFailed:
            return "The camera session could not be configured."
        case .captureFailed:
            return "The photo could not be captured."
        }
    }
}

final class CameraSessionController: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "breadcrumb.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var captureContinuation: CheckedContinuation<UIImage, Error>?

    func requestAccessIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status

        switch status {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        self?.configureAndStartSession()
                    }
                }
            }
        default:
            break
        }
    }

    func stopSession() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto() async throws -> UIImage {
        guard authorizationStatus == .authorized else {
            throw CameraCaptureError.permissionDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                self.captureContinuation = continuation
                let settings = AVCapturePhotoSettings()
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async {
            do {
                try self.configureSessionIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            } catch {
                print("Breadcrumb camera setup failed: \(error.localizedDescription)")
            }
        }
    }

    private func configureSessionIfNeeded() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraCaptureError.configurationFailed
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw CameraCaptureError.configurationFailed
        }

        session.addInput(input)
        session.addOutput(photoOutput)
        isConfigured = true
    }
}

extension CameraSessionController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            captureContinuation?.resume(throwing: error)
            captureContinuation = nil
            return
        }

        guard
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else {
            captureContinuation?.resume(throwing: CameraCaptureError.captureFailed)
            captureContinuation = nil
            return
        }

        captureContinuation?.resume(returning: image)
        captureContinuation = nil
    }
}
