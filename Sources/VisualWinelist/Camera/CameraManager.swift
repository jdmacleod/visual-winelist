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
            await configure()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { await configure() } else { error = .permissionDenied }
        default:
            error = .permissionDenied
        }
    }

    func stopSession() {
        Task.detached { [session = self.session] in session.stopRunning() }
        isSessionRunning = false
    }

    func capturePhoto() async throws -> Data {
        // macOS Continuity Camera "Video Effects" (Reactions) renders gesture-triggered
        // RealityKit overlays inside the capture pipeline; when that renderer glitches
        // (see "VFXNode... patching invalid duplicated core entity handle" in the
        // console) it can intermittently corrupt a single frame's photo data. Retry a
        // few times before surfacing an error, since the next frame is usually clean.
        var lastError: Error = CameraError.captureError("Unknown failure")
        for attempt in 1...3 {
            do {
                return try await capturePhotoOnce()
            } catch {
                lastError = error
                print("[Camera] capture attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
        throw lastError
    }

    private func capturePhotoOnce() async throws -> Data {
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

        // AVCaptureSession.startRunning() blocks until the session is live — run on a background thread.
        // Returns true on success so we can update MainActor state after awaiting.
        let started = await Task.detached(priority: .userInitiated) { () -> Bool in
            session.beginConfiguration()
            session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device)
            else {
                session.commitConfiguration()
                return false
            }

            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            session.commitConfiguration()
            session.startRunning()
            return true
        }.value

        // Back on MainActor — session.startRunning() has completed
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
        // Extract data here (nonisolated) before crossing to MainActor — Data is Sendable.
        let capturedData: Data? = error == nil ? photo.fileDataRepresentation() : nil
        let capturedError = error
        print(
            "[Camera] didFinishProcessingPhoto: error=\(capturedError?.localizedDescription ?? "nil") dataBytes=\(capturedData?.count ?? -1)"
        )

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
