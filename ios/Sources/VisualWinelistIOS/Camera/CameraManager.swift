@preconcurrency import AVFoundation
import Foundation

enum CameraError: Error, LocalizedError, Equatable {
    case permissionDenied
    case deviceUnavailable
    case captureError(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access is required. Enable it in Settings > Privacy & Security > Camera."
        case .deviceUnavailable:
            return "No rear camera found on this device."
        case .captureError(let msg):
            return "Capture failed: \(msg)"
        }
    }
}

@MainActor
class CameraManager: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var error: CameraError?

    nonisolated let session = AVCaptureSession()
    private nonisolated let photoOutput = AVCapturePhotoOutput()
    private nonisolated let sessionQueue = DispatchQueue(label: "com.visualwinelist.camera.session")

    private var photoContinuation: CheckedContinuation<Data, Error>?

    func startSession() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await configure()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { await configure() } else { error = .permissionDenied }
        default:
            error = .permissionDenied
        }
    }

    func stopSession() {
        sessionQueue.async { [session = self.session] in session.stopRunning() }
        isSessionRunning = false
    }

    func resumeSession() {
        sessionQueue.async { [session = self.session] in session.startRunning() }
        isSessionRunning = true
    }

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Private

    private func configure() async {
        let session = self.session
        let photoOutput = self.photoOutput
        let sessionQueue = self.sessionQueue

        let started: Bool = await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.beginConfiguration()
                session.sessionPreset = .photo

                // Prefer the rear wide-angle camera on iPhone/iPad
                let device =
                    AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video)
                guard let device,
                    let input = try? AVCaptureDeviceInput(device: device)
                else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }

                if session.canAddInput(input) { session.addInput(input) }
                if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
                session.commitConfiguration()
                session.startRunning()
                continuation.resume(returning: true)
            }
        }

        if started {
            isSessionRunning = true
        } else {
            error = .deviceUnavailable
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        let capturedData: Data? = error == nil ? photo.fileDataRepresentation() : nil
        let capturedError = error

        Task { @MainActor in
            if let capturedError {
                self.photoContinuation?.resume(
                    throwing: CameraError.captureError(capturedError.localizedDescription))
            } else if let data = capturedData {
                self.photoContinuation?.resume(returning: data)
            } else {
                self.photoContinuation?.resume(
                    throwing: CameraError.captureError("No image data returned"))
            }
            self.photoContinuation = nil
        }
    }
}
