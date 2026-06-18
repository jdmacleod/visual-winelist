import SwiftUI

struct WineGridView: View {
    @ObservedObject var viewModel: WineListViewModel
    let onScanMore: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.wines) { state in
                    NavigationLink {
                        WineDetailView(state: state)
                    } label: {
                        WineBottleCard(state: state)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            if viewModel.isScanning {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text(viewModel.scanMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 16)
            }
        }
        .safeAreaInset(edge: .bottom) {
            scanMoreBar
        }
    }

    private var scanMoreBar: some View {
        HStack {
            Text("\(viewModel.wines.count) wine\(viewModel.wines.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onScanMore) {
                Label("Scan more", systemImage: "camera.viewfinder")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isScanning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
