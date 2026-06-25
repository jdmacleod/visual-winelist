import SwiftUI

/// Landing hub. Gives Cancel and Settings a permanent destination instead of
/// dropping the user back onto the camera. Scanning is still one tap away via
/// the dominant primary action.
struct HomeView: View {
    var viewModel: WineListViewModel
    let onScan: () -> Void
    let onViewResults: () -> Void

    private var hasResults: Bool { !viewModel.wines.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if case .degraded(let detail) = viewModel.backendStatus {
                    degradedBanner(detail)
                }

                Spacer()
                brand
                Spacer()
                actions
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PreferencesView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    // MARK: - Sections

    private var brand: some View {
        VStack(spacing: 16) {
            Image(systemName: "wineglass")
                .font(.system(size: 64))
                .foregroundStyle(.wineRed)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Visual Wine List")
                    .font(.largeTitle.bold())
                Text("Scan a wine list. See bottles and tasting notes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: onScan) {
                Label("Scan a Wine List", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.wineRed)
            .accessibilityHint("Opens the camera to scan a wine list")

            if hasResults {
                Button(action: onViewResults) {
                    Label(
                        "View last results (\(viewModel.wines.count))",
                        systemImage: "square.grid.2x2"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 30)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func degradedBanner(_ detail: String) -> some View {
        NavigationLink {
            PreferencesView()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Backend setup needed")
                        .font(.caption.bold())
                    Text(detail)
                        .font(.caption2)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: .cornerRadiusMedium))
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .accessibilityLabel("Backend setup needed. \(detail). Opens Settings.")
    }
}
