import AVFoundation
import SwiftUI
import UIKit

struct CameraCaptureView: View {
    let title: String
    let subtitle: String
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var cameraController = CameraSessionController()
    @State private var isCapturing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if cameraController.authorizationStatus == .authorized {
                    ZStack {
                        CameraPreviewContainer(session: cameraController.session)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                        if !cameraController.isSessionReady {
                            ProgressView("Starting camera...")
                                .tint(.white)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding()
                } else {
                    permissionFallback
                        .padding(24)
                }

                captureBar
            }
        }
        .task {
            cameraController.requestAccessIfNeeded()
        }
        .onDisappear {
            cameraController.stopSession()
        }
        .alert("Camera Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: cameraController.sessionErrorMessage) { _, newValue in
            if let newValue {
                errorMessage = newValue
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Close") {
                    dismiss()
                }
                .foregroundStyle(.white)

                Spacer()
            }

            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var permissionFallback: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)

            Text(permissionTitle)
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(permissionMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))

            if cameraController.authorizationStatus == .denied {
                Button("Open Settings") {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(settingsURL)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var captureBar: some View {
        VStack(spacing: 14) {
            Button {
                capture()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 74, height: 74)
                    Circle()
                        .stroke(Color.black.opacity(0.2), lineWidth: 2)
                        .frame(width: 64, height: 64)
                }
            }
            .disabled(isCapturing || cameraController.authorizationStatus != .authorized || !cameraController.isSessionReady)

            if isCapturing {
                ProgressView("Saving frame...")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else {
                Text("Tap once to save this photo.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.bottom, 28)
    }

    private func capture() {
        isCapturing = true

        Task {
            do {
                let image = try await cameraController.capturePhoto()
                isCapturing = false
                onCapture(image)
                dismiss()
            } catch {
                isCapturing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private var permissionTitle: String {
        switch cameraController.authorizationStatus {
        case .denied:
            return "Camera access is turned off"
        case .restricted:
            return "Camera access is restricted"
        default:
            return "Camera access is needed"
        }
    }

    private var permissionMessage: String {
        switch cameraController.authorizationStatus {
        case .denied:
            return "Breadcrumb uses the camera to observe scenes, discover object candidates, and optionally capture reference photos. Enable access in Settings to continue."
        case .restricted:
            return "This device is not allowing camera access right now, so Breadcrumb cannot observe scenes or capture optional reference photos."
        default:
            return "Breadcrumb keeps captures and inferred events on this device."
        }
    }
}

struct CameraPreviewContainer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.videoPreviewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
