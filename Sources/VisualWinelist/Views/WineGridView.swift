import SwiftUI

struct WineGridView: View {
    @ObservedObject var viewModel: WineListViewModel
    let onScanMore: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.wines) { state in
                        WineBottleCard(state: state) {
                            viewModel.selectedWine = state.wine
                        }
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

            Divider()
            toolbar
        }
        .sheet(item: Binding(
            get: { viewModel.selectedWine.flatMap { w in viewModel.wines.first(where: { $0.wine == w }) } },
            set: { _ in viewModel.selectedWine = nil }
        )) { state in
            WineDetailView(state: state)
        }
    }

    private var toolbar: some View {
        HStack {
            Text("\(viewModel.wines.count) wine\(viewModel.wines.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                viewModel.clear()
                onScanMore()
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isScanning || viewModel.wines.isEmpty)
            Button {
                onScanMore()
            } label: {
                Label("Scan more", systemImage: "camera.viewfinder")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isScanning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
