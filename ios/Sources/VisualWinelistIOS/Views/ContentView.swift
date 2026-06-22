import SwiftUI
import UIKit

enum AppPhase {
    case camera, scanning, grid, error(String)
}

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var viewModel: WineListViewModel
    @State private var phase: AppPhase = .camera

    init(backendURL: URL) {
        _viewModel = StateObject(wrappedValue: WineListViewModel(backendURL: backendURL))
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
        .onChange(of: camera.error) { err in
            if let err { phase = .error(err.localizedDescription) }
        }
        .onChange(of: viewModel.errorMessage) { msg in
            if let msg { phase = .error(msg) } else if !viewModel.wines.isEmpty { phase = .grid }
        }
        .onChange(of: viewModel.wines.count) { count in
            if count > 0, case .scanning = phase {
                phase = .grid
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .onChange(of: viewModel.isScanning) { isScanning in
            UIApplication.shared.isIdleTimerDisabled = isScanning
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
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
        .onAppear { camera.session.startRunning() }
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
            if viewModel.wines.isEmpty {
                await viewModel.scan(photoData: photoData)
            } else {
                await viewModel.appendScan(photoData: photoData)
                if !viewModel.wines.isEmpty && viewModel.errorMessage == nil { phase = .grid }
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
}
