import AVFoundation
import SwiftUI
import UIKit

struct PreferencesView: View {
    @AppStorage(UserDefaultsKey.showPriceOverlay) private var showPriceOverlay = false
    @AppStorage(UserDefaultsKey.sendDiagnostics) private var sendDiagnostics = false
    @AppStorage(UserDefaultsKey.saveScanImages) private var saveScanImages = false
    @AppStorage(UserDefaultsKey.scanImageRetention) private var scanImageRetention = 50
    @AppStorage("BACKEND_URL") private var backendURL = ""

    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var showBackendEditor = false
    @State private var showClearTelemetryConfirm = false
    @State private var clearResult: String?

    private var validBackendURL: URL? {
        guard let url = URL(string: backendURL), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    var body: some View {
        Form {
            displaySection
            cameraSection
            scanPhotosSection
            diagnosticsSection
            backendSection
            aboutSection
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { cameraStatus = AVCaptureDevice.authorizationStatus(for: .video) }
        .sheet(isPresented: $showBackendEditor) {
            BackendURLEditor(currentURL: backendURL) { newValue in
                backendURL = newValue
            }
        }
    }

    // MARK: - Sections

    private var displaySection: some View {
        Section("Wine List Display") {
            Toggle("Show price on card", isOn: $showPriceOverlay)
        }
    }

    @ViewBuilder
    private var cameraSection: some View {
        Section {
            LabeledContent("Camera access", value: cameraStatusText)
            switch cameraStatus {
            case .notDetermined:
                Button("Allow camera access") {
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    }
                }
            case .denied, .restricted:
                Button("Open Settings") { openSystemSettings() }
            default:
                EmptyView()
            }
        } header: {
            Text("Camera")
        } footer: {
            if cameraStatus == .denied || cameraStatus == .restricted {
                Text("Scanning needs the camera. Enable it in Settings to scan wine lists.")
            }
        }
    }

    @ViewBuilder
    private var scanPhotosSection: some View {
        Section {
            Toggle("Save scan photos on server", isOn: $saveScanImages)
            if saveScanImages {
                Picker("Keep most recent", selection: $scanImageRetention) {
                    Text("20").tag(20)
                    Text("50").tag(50)
                    Text("100").tag(100)
                }
            }
        } header: {
            Text("Scan Photos")
        } footer: {
            Text(
                "When on, each scanned photo is stored on your backend so you can review what "
                    + "the model saw. Older photos beyond the limit are deleted. Off by default."
            )
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {
            Toggle("Send Diagnostics?", isOn: $sendDiagnostics)
            if sendDiagnostics {
                DisclosureGroup("What's sent") {
                    Text(
                        "Per-scan timing (network, analyze, image, notes), wine count, app "
                            + "version, git build, and device model. No photo, no wine names, no "
                            + "tasting notes."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if let url = validBackendURL {
                NavigationLink {
                    TelemetryReportsView(backendURL: url)
                } label: {
                    Text("View recent reports")
                }
                Button(role: .destructive) {
                    showClearTelemetryConfirm = true
                } label: {
                    Text("Clear telemetry data")
                }
            }
            if let clearResult {
                Text(clearResult).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Helps diagnose scan performance against your backend. Off by default.")
        }
        .confirmationDialog(
            "Delete all stored telemetry reports from the backend?",
            isPresented: $showClearTelemetryConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete all", role: .destructive) {
                Task { await clearTelemetry() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func clearTelemetry() async {
        guard let url = validBackendURL else { return }
        do {
            let deleted = try await BackendClient(baseURL: url).clearTelemetry()
            clearResult = "Cleared \(deleted) report\(deleted == 1 ? "" : "s")."
        } catch {
            clearResult = "Couldn't clear telemetry. Check the backend connection."
        }
    }

    private var backendSection: some View {
        Section {
            LabeledContent("URL", value: backendURL.isEmpty ? "Not set" : backendURL)
            Button("Change backend…") { showBackendEditor = true }
        } header: {
            Text("Backend")
        } footer: {
            Text("Changing this reconnects the app to a different backend server.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.appVersionString)
        }
    }

    // MARK: - Helpers

    private var cameraStatusText: String {
        switch cameraStatus {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Sheet for changing the backend URL. Mirrors SetupView's validation; only
/// commits a valid http(s) URL when the user taps Update.
private struct BackendURLEditor: View {
    let currentURL: String
    let onUpdate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @State private var error: String?

    init(currentURL: String, onUpdate: @escaping (String) -> Void) {
        self.currentURL = currentURL
        self.onUpdate = onUpdate
        _input = State(initialValue: currentURL)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.100:8000", text: $input)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Both devices must be on the same Wi-Fi network.")
                }
            }
            .navigationTitle("Change Backend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") { commit() }
                }
            }
        }
    }

    private func commit() {
        let raw = input.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else {
            error = "Enter a valid http(s) URL"
            return
        }
        onUpdate(url.absoluteString)
        dismiss()
    }
}
