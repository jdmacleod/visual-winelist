import SwiftUI

enum AppPhase {
    case camera
    case scanning
    case grid
    case error(String)
}

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var viewModel: WineListViewModel
    @State private var phase: AppPhase = .camera

    init(backendURL: URL) {
        _viewModel = StateObject(wrappedValue: WineListViewModel(backendURL: backendURL))
    }

    var body: some View {
        ZStack {
            switch phase {
            case .camera:
                cameraView
            case .scanning:
                scanningView
            case .grid:
                WineGridView(viewModel: viewModel, onScanMore: switchToCamera)
                    .frame(minWidth: 560, minHeight: 480)
            case .error(let message):
                errorView(message)
            }
        }
        .frame(width: 580, height: 520)
        .task { await camera.startSession() }
        .task { await viewModel.checkHealth() }
        .onChange(of: camera.error) { _, err in
            if let err { phase = .error(err.localizedDescription) }
        }
        .onChange(of: viewModel.errorMessage) { _, msg in
            if let msg {
                phase = .error(msg)
            } else if !viewModel.wines.isEmpty {
                phase = .grid
            }
        }
        .onChange(of: viewModel.wines.count) { old, new in
            if old == 0 && new > 0 { phase = .grid }
        }
    }

    // MARK: - Camera view

    private var cameraView: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            // Guide overlay
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                .padding(32)

            VStack {
                // Degraded backend warning banner
                if case .degraded(let reason) = viewModel.backendStatus {
                    Text("⚠ Backend degraded: \(reason)")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 12)
                }
                Spacer()
                Group {
                    if camera.isSessionRunning {
                        Text("Point at wine list, then tap to scan")
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.7).tint(.white)
                            Text("Starting camera…")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .padding(8)
                .background(.black.opacity(0.4), in: Capsule())
                .padding(.bottom, 20)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await capture() } }
        .overlay(alignment: .topLeading) {
            if !viewModel.wines.isEmpty {
                Button("← Back to cellar") { phase = .grid }
                    .buttonStyle(.bordered)
                    .padding(12)
            }
        }
    }

    // MARK: - Scanning view

    private var scanningView: some View {
        ZStack {
            Color.black
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text(viewModel.scanMessage.isEmpty ? "Scanning wine list…" : viewModel.scanMessage)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .animation(.default, value: viewModel.scanMessage)
                Button("Cancel") {
                    viewModel.cancelScan()
                    phase = .camera
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Error view

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
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
    }

    // MARK: - Actions

    private func capture() async {
        guard camera.isSessionRunning else { return }
        phase = .scanning

        do {
            let photoData = try await camera.capturePhoto()
            if viewModel.wines.isEmpty {
                await viewModel.scan(photoData: photoData)
            } else {
                await viewModel.appendScan(photoData: photoData)
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func switchToCamera() {
        phase = .camera
    }
}
