import AVFoundation
import CoreImage
import SwiftUI
import UIKit

enum CameraCaptureError: LocalizedError {
    case permissionDenied
    case configurationFailed
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access is required to observe objects and build the memory graph."
        case .configurationFailed:
            return "The camera session could not be configured."
        case .captureFailed:
            return "The photo could not be captured."
        }
    }
}

struct CameraVideoFrame: @unchecked Sendable {
    let cgImage: CGImage
    let timestamp: Date
    let presentationTimestamp: CMTime
}

final class CameraSessionController: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isSessionReady = false
    @Published private(set) var sessionErrorMessage: String?
    @Published private(set) var droppedFrameCount = 0

    let session = AVCaptureSession()
    var frameHandler: ((CameraVideoFrame) -> Void)?

    private let sessionQueue = DispatchQueue(label: "breadcrumb.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext()
    private var isConfigured = false
    private var captureContinuation: CheckedContinuation<UIImage, Error>?
    private var lastFrameTimestamp = Date.distantPast
    private var frameInterval: TimeInterval = 1.0
    private var isStreamingFrames = false
    private var streamStartDate: Date?
    private var streamStartPresentationTime: CMTime?

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

    func startFrameDelivery(interval: TimeInterval = 1.0) {
        frameInterval = interval
        lastFrameTimestamp = .distantPast
        isStreamingFrames = true
        streamStartDate = nil
        streamStartPresentationTime = nil
        droppedFrameCount = 0
    }

    func stopFrameDelivery() {
        isStreamingFrames = false
        streamStartDate = nil
        streamStartPresentationTime = nil
    }

    func stopSession() {
        stopFrameDelivery()
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionReady = false
            }
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
                DispatchQueue.main.async {
                    self.sessionErrorMessage = nil
                    self.isSessionReady = self.session.isRunning
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSessionReady = false
                    self.sessionErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func configureSessionIfNeeded() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }
        defer { session.commitConfiguration() }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraCaptureError.configurationFailed
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input), session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
            throw CameraCaptureError.configurationFailed
        }

        try configureFrameRate(for: camera)

        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        session.addInput(input)
        session.addOutput(photoOutput)
        session.addOutput(videoOutput)

        if let videoConnection = videoOutput.connection(with: .video) {
            applyPortraitRotation(to: videoConnection)
        }
        if let photoConnection = photoOutput.connection(with: .video) {
            applyPortraitRotation(to: photoConnection)
        }
        isConfigured = true
    }

    private func configureFrameRate(for camera: AVCaptureDevice) throws {
        let targetDuration = CMTime(value: 1, timescale: 15)
        let supportsTargetDuration = camera.activeFormat.videoSupportedFrameRateRanges.contains { range in
            CMTimeCompare(targetDuration, range.minFrameDuration) >= 0
                && CMTimeCompare(targetDuration, range.maxFrameDuration) <= 0
        }

        guard supportsTargetDuration else { return }

        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        camera.activeVideoMinFrameDuration = targetDuration
        camera.activeVideoMaxFrameDuration = targetDuration
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

extension CameraSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isStreamingFrames else { return }

        let sampleTimestamp = captureDate(for: sampleBuffer)
        guard sampleTimestamp.timeIntervalSince(lastFrameTimestamp) >= frameInterval else { return }
        lastFrameTimestamp = sampleTimestamp

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let normalized = normalizedImage(from: cgImage)
        guard let normalizedCGImage = normalized.cgImage else { return }
        let frame = CameraVideoFrame(
            cgImage: normalizedCGImage,
            timestamp: sampleTimestamp,
            presentationTimestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        )
        DispatchQueue.main.async { [frameHandler] in
            frameHandler?(frame)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isStreamingFrames else { return }
        DispatchQueue.main.async {
            self.droppedFrameCount += 1
        }
    }

    private func captureDate(for sampleBuffer: CMSampleBuffer) -> Date {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid else { return Date() }

        if streamStartPresentationTime == nil || streamStartDate == nil {
            streamStartPresentationTime = presentationTime
            streamStartDate = Date()
        }

        guard let streamStartPresentationTime, let streamStartDate else {
            return Date()
        }

        let delta = CMTimeSubtract(presentationTime, streamStartPresentationTime)
        let seconds = CMTimeGetSeconds(delta)
        guard seconds.isFinite else {
            return Date()
        }

        return streamStartDate.addingTimeInterval(max(0, seconds))
    }
}

private func normalizedImage(from cgImage: CGImage) -> UIImage {
    let image = UIImage(cgImage: cgImage)
    let renderer = UIGraphicsImageRenderer(size: image.size)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
}

private func applyPortraitRotation(to connection: AVCaptureConnection) {
    let portraitAngle: CGFloat = 90
    if connection.isVideoRotationAngleSupported(portraitAngle) {
        connection.videoRotationAngle = portraitAngle
    }
}
