import SwiftUI
import UIKit

enum AppPhase {
    case camera, scanning, grid, error(String)
}

struct ContentView: View {
    @State private var camera = CameraManager()
    @State private var viewModel: WineListViewModel
    @State private var phase: AppPhase = .camera

    init(backendURL: URL) {
        _viewModel = State(initialValue: WineListViewModel(backendURL: backendURL))
    }

    var body: some View {
        Group {
            switch phase {
            case .camera:
                cameraView
            case .scanning:
                scanningView
            case .grid:
                gridView
            case .error(let message):
                errorView(message)
            }
        }
        .task { await camera.startSession() }
        .task { await viewModel.checkHealth() }
        .onChange(of: camera.error) { _, err in
            if let err { phase = .error(err.localizedDescription) }
        }
        .onChange(of: viewModel.errorMessage) { _, msg in
            if let msg { phase = .error(msg) }
        }
        .onChange(of: viewModel.wines.count) { _, count in
            if count > 0, case .scanning = phase {
                phase = .grid
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .onChange(of: viewModel.isScanning) { _, isScanning in
            UIApplication.shared.isIdleTimerDisabled = isScanning
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        #if DEBUG
            .overlay(alignment: .bottomTrailing) {
                DebugHUD()
            }
        #endif
    }

    // MARK: - Camera view

    private var cameraView: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            VStack {
                // Degraded backend banner — tap to open Settings
                if case .degraded = viewModel.backendStatus {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Setup needed — open Settings", systemImage: "gear")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: .cornerRadiusSmall))
                    }
                    .padding(.top, 8)
                }

                Spacer()

                // Shutter button + hint
                VStack(spacing: 16) {
                    Group {
                        if camera.isSessionRunning {
                            Text("Point at wine list and tap to scan")
                        } else {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7).tint(.white)
                                Text("Starting camera…")
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8)
                    .background(.black.opacity(0.4), in: Capsule())

                    Button {
                        Task { await capture() }
                    } label: {
                        ZStack {
                            Circle().fill(.white).frame(width: 72, height: 72)
                            Circle().stroke(.white.opacity(0.5), lineWidth: 4).frame(width: 84, height: 84)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
                    }
                    .disabled(!camera.isSessionRunning)
                    .padding(.bottom, 50)
                    .accessibilityLabel("Capture wine list")
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if !viewModel.wines.isEmpty {
                Button {
                    phase = .grid
                } label: {
                    Label("Results", systemImage: "list.bullet")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: .cornerRadiusMedium))
                }
                .padding()
            }
        }
        .onAppear { camera.resumeSession() }
    }

    // MARK: - Scanning view

    private var scanningView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text(viewModel.scanMessage.isEmpty ? "Scanning wine list…" : viewModel.scanMessage)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .animation(.default, value: viewModel.scanMessage)
                    .padding(.horizontal, 32)

                Button("Cancel") {
                    viewModel.cancelScan()
                    phase = .camera
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Grid view

    private var gridView: some View {
        NavigationStack {
            WineGridView(viewModel: viewModel) {
                phase = .camera
            }
            .navigationTitle("Wine List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        viewModel.clear()
                        phase = .camera
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(viewModel.isScanning)
                    .accessibilityLabel("Clear all wines")
                }
            }
        }
    }

    // MARK: - Error view

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Button("Try again") {
                viewModel.errorMessage = nil
                phase = .camera
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    // MARK: - Actions

    private func capture() async {
        guard camera.isSessionRunning else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        phase = .scanning
        do {
            let photoData = try await camera.capturePhoto()
            camera.stopSession()
            #if DEBUG
                if let origImg = UIImage(data: photoData) {
                    DebugStore.shared.stageOriginalSize(
                        width: Int(origImg.size.width * origImg.scale),
                        height: Int(origImg.size.height * origImg.scale)
                    )
                }
            #endif
            let uploadData = await Task.detached(priority: .userInitiated) {
                resizeForUpload(photoData)
            }.value
            if viewModel.wines.isEmpty {
                await viewModel.scan(photoData: uploadData)
            } else {
                await viewModel.appendScan(photoData: uploadData)
                if !viewModel.wines.isEmpty && viewModel.errorMessage == nil { phase = .grid }
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

}

func resizeForUpload(_ data: Data) -> Data {
    guard let image = UIImage(data: data) else { return data }
    let maxSide = CGFloat(ScanSettings.uploadMaxSide)
    // UIImage.size is in points; multiply by scale to get pixel dimensions.
    // Without this, a 4320×5760 photo on a 3× device reports size=(1440,1920)
    // and the guard fails silently (1920 > 1920 is false).
    let pixelW = image.size.width * image.scale
    let pixelH = image.size.height * image.scale
    guard max(pixelW, pixelH) > maxSide else { return data }
    let downscale = maxSide / max(pixelW, pixelH)
    let targetPixels = CGSize(
        width: (pixelW * downscale).rounded(),
        height: (pixelH * downscale).rounded()
    )
    // format.scale = 1 → renderer works in pixels directly; default (device screen
    // scale) would multiply targetPixels by 3× on a Pro device.
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: targetPixels, format: format)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetPixels)) }
    return resized.jpegData(compressionQuality: ScanSettings.uploadJPEGQuality) ?? data
}
