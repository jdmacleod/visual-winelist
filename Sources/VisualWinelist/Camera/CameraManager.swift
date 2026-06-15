@preconcurrency import AVFoundation
import Foundation

enum CameraError: Error, LocalizedError, Equatable {
    case permissionDenied
    case deviceUnavailable
    case captureError(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access is required. Enable it in System Settings > Privacy & Security > Camera."
        case .deviceUnavailable:
            return "No camera found on this Mac."
        case .captureError(let msg):
            return "Capture failed: \(msg)"
        }
    }
}

@MainActor
class CameraManager: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var error: CameraError?

    // nonisolated let: accessible from non-actor contexts (preview layer, background tasks)
    nonisolated let session = AVCaptureSession()
    private nonisolated let photoOutput = AVCapturePhotoOutput()

    private var photoContinuation: CheckedContinuation<Data, Error>?

    func startSession() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configure()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { configure() } else { error = .permissionDenied }
        default:
            error = .permissionDenied
        }
    }

    func stopSession() {
        Task.detached { [session = self.session] in session.stopRunning() }
        isSessionRunning = false
    }

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Private

    private func configure() {
        let session = self.session
        let photoOutput = self.photoOutput

        Task.detached(priority: .userInitiated) {
            session.beginConfiguration()
            session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device)
            else {
                session.commitConfiguration()
                await MainActor.run { self.error = .deviceUnavailable }
                return
            }

            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            session.commitConfiguration()

            session.startRunning()
            await MainActor.run { self.isSessionRunning = true }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        // Extract data here (nonisolated) before crossing to MainActor — Data is Sendable.
        let capturedData: Data? = error == nil ? photo.fileDataRepresentation() : nil
        let capturedError = error

        Task { @MainActor in
            if let capturedError {
                self.photoContinuation?.resume(throwing: CameraError.captureError(capturedError.localizedDescription))
            } else if let data = capturedData {
                self.photoContinuation?.resume(returning: data)
            } else {
                self.photoContinuation?.resume(throwing: CameraError.captureError("No image data returned"))
            }
            self.photoContinuation = nil
        }
    }
}
